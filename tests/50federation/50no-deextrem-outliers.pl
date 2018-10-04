test "Forward extremities remain so even after the next events are populated as outliers",
      requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( user_opts => { with_events => 1 } ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

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
      my ( $room, $pl_event_b );

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         ( $room ) = @_;

         # make sure that the sytest user has permission to alter the state
         Future->needs_all(
            matrix_change_room_powerlevels( $creator, $room_id, sub {
               my ( $levels ) = @_;
               $levels->{users}->{$user_id} = 100;
            }),
            $inbound_server->await_event( "m.room.power_levels", $room_id, sub {1} )
            ->then( sub {
               ( $pl_event_b ) = @_;
               log_if_fail "Received PL event B", $pl_event_b;
               $room->insert_event( $pl_event_b );
               Future->done();
            }),
         );
      })->then( sub {
         my %state_before_c = %{ $room->{current_state} };

         # generate all of the events
         my $outlier_event_c = $room->create_and_insert_event(
            event_id_suffix => "outlier_C",
            type => "test_state",
            state_key => "C",
            sender  => $user_id,
            content => {
               body => "event_c",
            },
            # prev_events => SyTest::Federation::Room::make_event_refs( $pl_event_b ),
         );

         log_if_fail "Outlier event C", $outlier_event_c;

         my $backfilled_event_d = $room->create_and_insert_event(
            event_id_suffix => "backfilled_D",
            type => "message",
            sender  => $fake_user_id,
            content => {
               body => "event_d",
            },
         );

         my $sent_event_e = $room->create_and_insert_event(
            event_id_suffix => "sent_E",
            type => "message",
            sender  => $fake_user_id,
            content => {
               body => "event_e",
            },
         );

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
                  [ $sent_event_e->{event_id } ],
                  "latest_events in /get_missing_events request",
               );

               # just return D
               $req->respond_json( {
                  events => [ $backfilled_event_d ],
               } );

               Future->done(1);
            }),

            $inbound_server->await_request_state_ids(
               $room_id, $outlier_event_c->{event_id},
            )->then( sub {
               my ( $req ) = @_;
               log_if_fail "/state_ids request";

               my $resp = {
                  pdu_ids => [
                     map { $_->{event_id} } values( %state_before_c ),
                  ],
                  auth_chain_ids => [
                     # XXX we're supposed to return the whole auth chain here,
                     # not just c's auth_events. It doesn't matter too much
                     # here though.
                     map { $_->[0] } @{ $outlier_event_c->{auth_events} },
                  ],
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
                  [ $pl_event_b->{event_id} ],
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
