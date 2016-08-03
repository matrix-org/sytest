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

         assert_json_keys( $body, qw( pdus auth_chain ));
         assert_json_list( my $state = $body->{pdus} );

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

test "Outbound federation sends /state_ids",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
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
            $inbound_server->await_request_state_ids( $room_id )
            ->then( sub {
               my ( $req ) = @_;

               log_if_fail "Got /state_ids";

               $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );

               Future->done(1);
            }),
            $inbound_server->await_request_state( $room_id )
            ->then( sub {
               my ( $req ) = @_;

               log_if_fail "Got /state";

               $req->respond_json( {
                  pdus => [],
                  auth_chain => [],
               } );

               Future->done(1);
            }),
            $inbound_server->await_request_get_missing_events( $room_id )
            ->then( sub {
               my ( $req ) = @_;

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
         });
      });
   };
