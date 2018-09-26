sub get_state_ids_from_server {
   my ( $outbound_client, $server, $room_id, $event_id ) = @_;

   return $outbound_client->do_request_json(
      method   => "GET",
      hostname => $server,
      uri      => "/state_ids/$room_id/",
      params   => { event_id => $event_id },
   );
}

test "Inbound federation can get state for a room",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $info, undef, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $room;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         ( $room ) = @_;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/state/$room_id/",
            params   => {
               event_id => $room->{prev_events}[-1]->{event_id},
            }
         );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( pdus auth_chain ));
         assert_json_list( my $state = $body->{pdus} );

         my $create_event = $room->get_current_state_event( "m.room.create", "" );
         my $power_event = $room->get_current_state_event( "m.room.power_levels", "" );

         foreach my $ev ( $create_event, $power_event ) {
            log_if_fail "ev", $ev;
            my $type = $ev->{type};
            any { $_->{event_id} eq $ev->{event_id} } @{ $state }
               or die "Missing $type event";
         }

         Future->done(1);
      });
   };

test "Inbound federation can get state_ids for a room",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $info, undef, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $room;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         ( $room ) = @_;

         get_state_ids_from_server(
            $outbound_client, $first_home_server,
            $room_id, $room->{prev_events}[-1]->{event_id},
         );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( pdu_ids auth_chain_ids ));
         assert_json_list( my $state = $body->{pdu_ids} );

         my $create_event = $room->get_current_state_event( "m.room.create", "" );
         my $power_event = $room->get_current_state_event( "m.room.power_levels", "" );

         foreach my $ev ( $create_event, $power_event ) {
            log_if_fail "ev", $ev;
            my $type = $ev->{type};
            any { $_ eq $ev->{event_id} } @{ $state }
               or die "Missing $type event";
         }

         Future->done(1);
      });
   };

test "Outbound federation requests /state_ids and correctly handles 404",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( user_opts => { with_events => 1 } ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $room;
      my $sent_event;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         ( $room ) = @_;

         # Generate but don't send an event
         my $missing_event = $room->create_and_insert_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Message 1",
            },
         );

         # Generate another one and do send it so it will refer to the
         # previous in its prev_events field
         $sent_event = $room->create_and_insert_event(
            type => "m.room.message",

            # This would be done by $room->create_and_insert_event anyway but lets be
            #   sure for this test
            prev_events => [
               [ $missing_event->{event_id}, $missing_event->{hashes} ],
            ],

            sender  => $user_id,
            content => {
               body => "Message 2",
            },
         );

         Future->wait_all(
            $inbound_server->await_request_get_missing_events( $room_id )
            ->then( sub {
               my ( $req ) = @_;

               # We return no events to force the remote to ask for state
               $req->respond_json( {
                  events => [],
               } );

               Future->done(1);
            }),

            $outbound_client->send_event(
               event       => $sent_event,
               destination => $first_home_server,
            ),
         );
       })->then( sub {
	  my @futureresults = @_;
	  if ($futureresults[1]->is_failed eq 0) { die "Should have failed"}

	  Future->done(1);
      })->then_done(1);
   };



test "Outbound federation requests missing prev_events and then asks for /state_ids and resolves the state",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( user_opts => { with_events => 1 } ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      # in this test, we're going to create a DAG like this:
      #
      #      A
      #     /
      #    B  (Y)
      #   / \ /
      #   |  X
      #   \ /
      #    C
      #
      # So we start with A and B, and then send C, which has prev_events (B,
      # X). We expect the remote server to request the missing events, and we
      # respond with X, which has another prev_event Y, which we don't send
      # proactively.
      #
      # In this case, we don't expect the remote server to go on requesting
      # missing events indefinitely - rather we expect it to stop after one
      # round and instead request the state at Y.
      #
      # In order to test the state resolution, we also have a couple of made-up
      # state events, S and T, which we stick in the response when we get the
      # state request.
      #
      # XXX: the number of rounds of get_missing_events which the server does
      # is an implementation detail - Synapse only does one round, but it is of
      # course valid to keep going for a while. We may need to update this test
      # to handle alternative implementations.

      my $pl_event_id;
      my $room;
      my $sent_event_b;

      # make sure that the sytest user has permission to alter the state
      matrix_change_room_powerlevels( $creator, $room_id, sub {
         my ( $levels ) = @_;

         $levels->{users}->{$user_id} = 100;
      })->then( sub {
         my ( $body ) = @_;
         $pl_event_id = $body->{event_id};

         $outbound_client->join_room(
            server_name => $first_home_server,
            room_id     => $room_id,
            user_id     => $user_id,
           );
      })->then( sub {
         ( $room ) = @_;

         # Create and send B
         $sent_event_b = $room->create_and_insert_event(
            type => "test_state",
            state_key => "B",

            sender  => $user_id,
            content => {
               body => "event_b",
            },
         );

         Future->needs_all(
            $outbound_client->send_event(
               event       => $sent_event_b,
               destination => $first_home_server,
            ),
            await_event_for( $creator, filter => sub {
               ( $_[0]->{event_id} // '' ) eq $sent_event_b->{event_id};
            }),
         );
      })->then( sub {
         # Generate our "missing" events
         my $missing_event_y = $room->create_event(
            type => "test_state",
            state_key => "Y",

            sender  => $user_id,
            content => {
               body => "event_y",
            },
         );

         my $missing_event_x = $room->create_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "event_x",
            },
            prev_events => SyTest::Federation::Room::make_event_refs(
               @{ $room->{prev_events} }, $missing_event_y,
            ),
         );

         my $missing_state_s = $room->create_event(
            type => "m.room.power_levels",
            state_key => "",
            sender  => $user_id,
            content => {
               users => {
                  $user_id => 100,
               },
            },
         );

         my $missing_state_t = $room->create_event(
            type => "test_state",
            state_key => "T",
            sender  => $user_id,
            content => { topic => "how now" },
         );

         # Now create and send our regular event C.
         my $sent_event_c = $room->create_and_insert_event(
            type => "m.room.message",

            prev_events => SyTest::Federation::Room::make_event_refs(
               @{ $room->{prev_events} }, $missing_event_x,
            ),

            sender  => $user_id,
            content => {
               body => "event_c",
            },
         );

         log_if_fail "Missing events X, Y: " . $missing_event_x->{event_id} .
            ", " . $missing_event_y->{event_id};
         log_if_fail "Sent events B, C: " . $sent_event_b->{event_id} .
            ", " . $sent_event_c->{event_id};

         Future->needs_all(
            $outbound_client->send_event(
               event       => $sent_event_c,
               destination => $first_home_server,
            ),

            $inbound_server->await_request_get_missing_events( $room_id )
            ->then( sub {
               my ( $req ) = @_;

               my $body = $req->body_from_json;
               log_if_fail "/get_missing_events request", $body;

               assert_deeply_eq(
                  $body->{latest_events},
                  [ $sent_event_c->{event_id } ],
                  "latest_events in /get_missing_events request",
               );

               # just return X
               $req->respond_json( {
                  events => [ $missing_event_x ],
               } );

               Future->done(1);
            }),

            $inbound_server->await_request_state_ids(
               $room_id, $missing_event_y->{event_id},
            )->then( sub {
               my ( $req ) = @_;
               log_if_fail "/state_ids request";

               # build a state map from the room's current state and our extra events
               my %state = %{ $room->{current_state} };
               foreach my $event ( $missing_state_s, $missing_state_t ) {
                  my $k = join "\0", $event->{type}, $event->{state_key};
                  $state{$k} = $event;
               }

               my $resp = {
                  pdu_ids => [
                     map { $_->{event_id} } values( %state ),
                  ],
                  auth_chain_ids => [
                     # XXX I'm not really sure why we have to return our
                     # auth_events here, when they are already in the event
                     map { $_->[0] } @{ $missing_event_y->{auth_events} },
                  ],
               };

               log_if_fail "/state_ids response", $resp;

               $req->respond_json( $resp );

               Future->done(1);
            }),
         )->then( sub {
            # creator user should eventually receive the events
            Future->needs_all(
               await_event_for( $creator, filter => sub {
                  ( $_[0]->{event_id} // '' ) eq $sent_event_c->{event_id};
               }),
               await_event_for( $creator, filter => sub {
                  ( $_[0]->{event_id} // '' ) eq $missing_event_x->{event_id};
               }),
            );
         })->then( sub {
            # check the 'current' state of the room after state resolution
            matrix_get_room_state_by_type( $creator, $room_id ) -> then( sub {
               my ( $state ) = @_;
               log_if_fail "final room state", $state;

               assert_eq(
                  $state->{"m.room.power_levels"}->{""}->{"event_id"},
                  $pl_event_id,
                  "power_levels event after state res",
               );

               assert_eq(
                  $state->{"test_state"}->{"B"}->{"event_id"},
                  $sent_event_b->{event_id},
                  "test_state B after state res",
               );

               assert_eq(
                  $state->{"test_state"}->{"T"}->{"event_id"},
                  $missing_state_t->{event_id},
                  "test_state T after state res",
               );

               assert_eq(
                  $state->{"test_state"}->{"Y"}->{"event_id"},
                  $missing_event_y->{event_id},
                  "test_state Y after state res",
               );

               Future->done(1);
            });
         })->then( sub {
            # check state at X
            get_state_ids_from_server(
               $outbound_client, $first_home_server,
               $room_id, $missing_event_x->{event_id},
            )->then( sub {
               my ( $body ) = @_;
               my $state_ids = $body->{pdu_ids};
               log_if_fail "State at X", $state_ids;
               for my $ev (
                  $pl_event_id,
                  $missing_state_t->{event_id},
                  $sent_event_b->{event_id},
                  $missing_event_y->{event_id},
               ) {
                  any { $_ eq $ev } @{ $state_ids }
                     or die "State $ev missing at X";
               }

               Future->done(1);
            });
         });
      });
   };

test "Getting state checks the events requested belong to the room",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],
   do => sub {
      my ( $outbound_client, $info, $priv_creator, $priv_room_id,
           $pub_creator, $pub_room_id, $fed_user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $priv_join_event;

      # Join the public room, but don't touch the private one
      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $pub_room_id,
         user_id     => $fed_user_id,
      )->then( sub {
         # Send an event into the private room
         matrix_send_room_text_message( $priv_creator, $priv_room_id,
            body => "Hello world",
         )
      })->then( sub {
         my ( $priv_event_id ) = @_;

         # We specifically use the public room, but the private event ID
         # That's the point of this test.
         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/state/$pub_room_id/",

            params => {
               event_id => $priv_event_id,
            }
         )->main::expect_m_not_found;
      });
   };


test "Getting state IDs checks the events requested belong to the room",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],
   do => sub {
      my ( $outbound_client, $info, $priv_creator, $priv_room_id,
           $pub_creator, $pub_room_id, $fed_user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $priv_join_event;

      # Join the public room, but don't touch the private one
      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $pub_room_id,
         user_id     => $fed_user_id,
      )->then( sub {
         # Send an event into the private room
         matrix_send_room_text_message( $priv_creator, $priv_room_id,
            body => "Hello world",
         )
      })->then( sub {
         my ( $priv_event_id ) = @_;

         # We specifically use the public room, but the private event ID
         # That's the point of this test.
         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/state_ids/$pub_room_id/",

            params => {
               event_id => $priv_event_id,
            }
         )->main::expect_m_not_found;
      });
   };
