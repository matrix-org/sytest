use Future::Utils qw( repeat );

test "Inbound federation can backfill events",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $user_id = "\@50fed-user:$local_server_name";

      my $join_event;

      # Create some past messages to backfill from
      ( repeat {
         matrix_send_room_text_message( $creator, $room_id,
            body => "Message $_[0] here",
         )
      } foreach => [ 1 .. 10 ] )->then( sub {
         $outbound_client->join_room(
            server_name => $first_home_server,
            room_id     => $room_id,
            user_id     => $user_id,
         );
      })->then( sub {
         my ( $room ) = @_;

         $join_event = $room->get_current_state_event( "m.room.member", $user_id );
         log_if_fail "Join event", $join_event;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/backfill/$room_id/",

            params => {
               v     => $join_event->{prev_events}[0][0],
               limit => 100,
            },
         );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Backfill response", $body;

         assert_json_keys( $body, qw( origin pdus ));

         assert_eq( $body->{origin}, $first_home_server,
            'body origin' );
         assert_json_list( my $events = $body->{pdus} );

         # Each element of @$events ought to look like an event. We won't
         # sanity-check it too far
         foreach my $event ( @$events ) {
            assert_json_keys( $event, qw( type event_id ));
         }

         assert_eq( $events->[0]{event_id}, $join_event->{prev_events}[0][0],
            'event_id of first returned event' );

         Future->done(1);
      });
   };
