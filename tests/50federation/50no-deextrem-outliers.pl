test "Forward extremities remain so even after the next events are populated as outliers",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER,
                 federated_rooms_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $creator, $user_id, $room ) = @_;
      my $first_home_server = $creator->server_name;

      # Here we create a straightforward dag like this:
      #
      #   A
      #   |
      #   B
      #   |
      #   C
      #   |
      #   D
      #   |
      #   E
      #
      # We start with a regular DAG, ending at B. We then create (but don't
      # yet send) a state event C, and one which we expect to be rejected, D.
      #
      # We then send another event which we expect to be rejected, E. E's
      # prev_event is D, which we expect to be fetched via get_missing_events.
      # D's prev_event is C, which we expect to be fetched and persisted as an
      # outlier (but not rejected).
      #
      # So, because C is populated as an outlier, and D and E are rejected, B
      # continues to be the only forward_extremity.
      #
      # There was previously a bug in synapse which would leave us with no
      # forward extremities in this situation and/or an exception
      # (https://github.com/matrix-org/synapse/issues/3883).

      my $fake_user_id = '@fake_user:' . $outbound_client->server_name;
      my $room_id = $room->room_id;
      my $pl_event_b_id;

      # make sure that the sytest user has permission to alter the state
      Future->needs_all(
         matrix_change_room_power_levels( $creator, $room_id, sub {
            my ( $levels ) = @_;
            $levels->{users}->{$user_id} = 100;
         })->on_done( sub {
            my ( $r ) = @_;
            my $event_id = $r->{ event_id };
            log_if_fail "Sent PL event B: $event_id";
         }),
         $inbound_server->await_event( "m.room.power_levels", $room_id, sub {1} )
         ->on_done( sub {
            my ( $pl_event_b ) = @_;
            $pl_event_b_id = $room->id_for_event( $pl_event_b );
         }),
      )->then( sub {
         my %state_before_c = %{ $room->{current_state} };

         log_if_fail "Starting room state", {
            map { $_ => $room->id_for_event( $state_before_c{ $_ }) } keys %state_before_c
         };

         my $pl_state = $state_before_c{"m.room.power_levels\0"};
         assert_eq( $room->id_for_event( $pl_state ), $pl_event_b_id, "PL state event id" );

         # generate all of the events
         my ( $outlier_event_c, $outlier_event_c_id ) = $room->create_and_insert_event(
            event_id_suffix => "outlier_C",
            type => "test_state",
            state_key => "C",
            sender  => $user_id,
            content => {
               body => "event_c",
            },
            # prev_events => $room->make_event_refs( $pl_event_b ),
         );

         log_if_fail "Outlier event C $outlier_event_c_id", $outlier_event_c;

         my ( $backfilled_event_d, $backfilled_event_d_id ) = $room->create_and_insert_event(
            event_id_suffix => "backfilled_D",
            type => "message",
            sender  => $fake_user_id,
            content => {
               body => "event_d",
            },
         );
         log_if_fail "Backfilled event D $backfilled_event_d_id", $backfilled_event_d;

         my ( $sent_event_e, $sent_event_e_id ) = $room->create_and_insert_event(
            event_id_suffix => "sent_E",
            type => "message",
            sender  => $fake_user_id,
            content => {
               body => "event_e",
            },
         );
         log_if_fail "Sent event E $sent_event_e_id", $sent_event_e;

         # do the send
         Future->needs_all(
            $outbound_client->send_event(
               event       => $sent_event_e,
               destination => $first_home_server,
            ),

            $inbound_server->await_request_get_missing_events( $room_id )
            ->then( sub {
               my ( $req ) = @_;

               my $body = $req->body_from_json;
               log_if_fail "/get_missing_events request", $body;

               assert_deeply_eq(
                  $body->{latest_events},
                  [ $sent_event_e_id ],
                  "latest_events in /get_missing_events request",
               );

               # just return D
               $req->respond_json( {
                  events => [ $backfilled_event_d ],
               } );

               Future->done(1);
            }),

            $inbound_server->await_request_state_ids(
               $room_id, $outlier_event_c_id,
            )->then( sub {
               my ( $req ) = @_;
               log_if_fail "/state_ids request";

               my $resp = {
                  pdu_ids => [
                     map { $room->id_for_event( $_ )} values( %state_before_c ),
                  ],

                  # XXX we're supposed to return the whole auth chain here,
                  # not just c's auth_events. It doesn't matter too much
                  # here though.
                  auth_chain_ids => $room->event_ids_from_refs(
                     $outlier_event_c->{auth_events},
                  ),
               };

               log_if_fail "/state_ids response", $resp;

               $req->respond_json( $resp );

               Future->done(1);
            }),
         )->then( sub {
            # at this point, B should still be the forward extremity.
            $outbound_client->get_remote_forward_extremities(
               server_name => $first_home_server,
               room_id => $room_id,
            )->then( sub {
               my ( @extremity_event_ids ) = @_;
               log_if_fail "Extremities after send", \@extremity_event_ids;
               assert_deeply_eq(
                  \@extremity_event_ids,
                  [ $pl_event_b_id ],
                  "forward extremities",
                 );
               Future->done(1);
            });
         })->then( sub {
            # send one more event, and check synapse still doesn't explosm.
            my $sent_event_f = $room->create_and_insert_event(
               event_id_suffix => "sent_F",
               type => "message",
               sender  => $fake_user_id,
               content => {
                  body => "event_f",
               },
            );

            $outbound_client->send_event(
               event       => $sent_event_f,
               destination => $first_home_server,
            );
         });
      });
   };
