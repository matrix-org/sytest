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

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/state_ids/$room_id/",
            params   => {
               event_id => $room->{prev_events}[-1]->{event_id},
            }
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

test "Federation rejects inbound events where the prev_events cannot be found",
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
         my $missing_event = $room->create_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Message 1",
            },
         );

         # Generate another one and do send it so it will refer to the
         # previous in its prev_events field
         $sent_event = $room->create_event(
            type => "m.room.message",

            # This would be done by $room->create_event anyway but lets be
            #   sure for this test
            prev_events => [
               [ $missing_event->{event_id}, $missing_event->{hashes} ],
            ],

            sender  => $user_id,
            content => {
               body => "Message 2",
            },
         );

         Future->needs_all(
            $inbound_server->await_request_get_missing_events( $room_id )
            ->then( sub {
               my ( $req ) = @_;

               # Return no events, which should cause a rejection.
               $req->respond_json( {
                  events => [],
               } );

               Future->done(1);
            }),

            $outbound_client->send_transaction(
               pdus => [ $sent_event ],
               destination => $first_home_server,
            )->then( sub {
               # we expect the event to be rejected.
               my ( $body ) = @_;
               log_if_fail "send_transaction response", $body;
               assert_ok(
                  defined( $body->{pdus}->{ $sent_event->{event_id} }->{error} ),
                  "/send accepted faulty event",
               );

               Future->done(1);
            }),
         );
      });
   };

test "Outbound federation requests /state_ids and asks for missing state",
   # Disabled as Synapse now checks the state of the missing item's ancestors instead
   bug => "DISABLED",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( user_opts => { with_events => 1 } ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $room;
      my $sent_event;
      my $missing_state;

      # make sure that the sytest user has permission to alter the state
      matrix_change_room_powerlevels( $creator, $room_id, sub {
         my ( $levels ) = @_;

         $levels->{users}->{$user_id} = 100;
      })->then( sub {
         $outbound_client->join_room(
            server_name => $first_home_server,
            room_id     => $room_id,
            user_id     => $user_id,
           );
      })->then( sub {
         ( $room ) = @_;

         # Generate but don't send an event
         my $missing_event = $room->create_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Message missing",
            },
         );

         $missing_state = $room->create_event(
            type      => "m.room.topic",
            state_key => "",

            sender  => $user_id,
            content => {
               topic => "Test topic",
            },
         );

         # Generate another one and do send it so it will refer to the
         # previous in its prev_events field
         $sent_event = $room->create_event(
            type => "m.room.message",

            # This would be done by $room->create_event anyway but lets be
            #   sure for this test
            prev_events => [
               [ $missing_event->{event_id}, $missing_event->{hashes} ],
            ],

            sender  => $user_id,
            content => {
               body => "Message sent",
            },
         );

         log_if_fail "Missing message: " . $missing_event->{event_id};
         log_if_fail "Missing topic: " . $missing_state->{event_id};
         log_if_fail "Sent message: " . $sent_event->{event_id};

         Future->needs_all(
            $inbound_server->await_request_state_ids( $room_id )
            ->then( sub {
               my ( $req ) = @_;

               log_if_fail "Got /state_ids request";

               my @auth_event_ids = map { $_->{event_id} } $room->current_state_events;

               # Don't need to be exact, synapse handles failure gracefully
               $req->respond_json( {
                  pdu_ids => [ $missing_state->{event_id}, @auth_event_ids ],
                  auth_chain_ids => [ @auth_event_ids ],
               } );

               Future->done(1);
            }),
            $inbound_server->await_request_event( $missing_state->{event_id} )
            ->then( sub {
               my ( $req ) = @_;

               log_if_fail "Got /event/ request";

               # Don't need to be exact, synapse handles failure gracefully
               $req->respond_json( {
                  pdus => [ $missing_state ],
               } );

               Future->done(1);
            }),
            $inbound_server->await_request_get_missing_events( $room_id )
            ->then( sub {
               my ( $req ) = @_;

               log_if_fail "Got /missing_events request";

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
         # creator user should eventually receive the sent event
         await_event_for( $creator, filter => sub {
            my ( $event ) = @_;
            return $event->{type} eq "m.room.message" &&
                   $event->{event_id} eq $sent_event->{event_id};
         })->on_done( sub {
            log_if_fail "Creator received sent event";
         });
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.topic",
            state_key => "",
         );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Returned body", $body;

         assert_eq( $body->{topic}, $missing_state->{content}{topic} );

         Future->done( 1 );
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
