test "Outbound federation can request missing events",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $missing_event;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         my ( $room ) = @_;

         # Generate but don't send an event
         $missing_event = $room->create_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Message 1",
            },
         );

         # Generate another one and do send it so it will refer to the
         # previous in its prev_events field
         my $sent_event = $room->create_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Message 2",
            },
         );

         Future->needs_all(
            $inbound_server->await_get_missing_events( $room_id )
            ->then( sub {
               my ( $req ) = @_;
               my $body = $req->body_from_json;

               assert_json_keys( $body, qw( earliest_events latest_events limit ));
               # TODO: min_depth but I have no idea what it does

               assert_json_list( $body->{earliest_events} );
               assert_json_list( $body->{latest_events} );

               my @events = $datastore->get_backfill_events(
                  start_at    => $body->{latest_events},
                  stop_before => $body->{earliest_events},
                  limit       => $body->{limit},
               );

               $req->respond_json( {
                  events => \@events,
               } );

               Future->done(1);
            }),

            $outbound_client->send_event(
               event       => $sent_event,
               destination => $first_home_server,
            ),
         );
      })->then( sub {
         # creator user should eventually receive the missing event
         await_event_for( $creator, filter => sub {
            my ( $event ) = @_;
            return $event->{type} eq "m.room.message" &&
                   $event->{event_id} eq $missing_event->{event_id};
         });
      });
   };

test "Inbound federation can return missing events",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 room_fixture( requires_users => [ local_user_fixture() ] ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $info, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         my ( $room ) = @_;

         # Find two event IDs that there's going to be something missing
         # inbetween. Say, any history between the room's creation and my own
         # joining of it.

         my $creation_event = $room->get_current_state_event( "m.room.create" );

         my $member_event = $room->get_current_state_event(
            "m.room.member", $user_id
         );

         $outbound_client->do_request_json(
            method   => "POST",
            hostname => $first_home_server,
            uri      => "/get_missing_events/" . $room->room_id,

            content => {
               earliest_events => [ $creation_event->{event_id} ],
               latest_events   => [ $member_event->{event_id} ],
               limit           => 10,
               min_depth       => 1,  # TODO(paul): find out what this is for
            },
         );
      })->then( sub {
         my ( $result ) = @_;
         log_if_fail "missing events result", $result;

         assert_json_keys( $result, qw( events ));
         assert_json_list( my $events = $result->{events} );

         # Just check that they all look like events.
         # TODO(paul): Some stronger assertions that these are the /correct/
         #   events that we actually asked for
         foreach my $event ( @$events ) {
            assert_json_keys( $event, qw( type event_id room_id ));

            assert_eq( $event->{room_id}, $room_id,
               'event room_id' );
         }

         Future->done(1);
      });
   };
