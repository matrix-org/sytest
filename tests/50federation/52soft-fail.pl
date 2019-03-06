test "Inbound federation correctly soft fails events",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( user_opts => { with_events => 1 }),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $room;

      # We'll grab out some event IDs to use as prev events
      my $join_event_id;
      my $power_level_event_id;
      my $denied_event_id;

      # We're going to construct a room graph like:
      #
      #        A
      #       / \
      #      B   C
      #       \ /
      #        D
      #
      # Where time is flowing downards and sent in alphabetical order.
      #
      #  A = join of remote user
      #  B = creator of room blocks message sending
      #  C = remote user sends a message
      #  D = remote user sends a non-mesasage event
      #
      # Since the banning of sending message happends before C, we expect the
      # local server to soft fail C when it is received. D should be received as
      # usual.

      # First we join the room (event A)
      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         ( $room ) = @_;

         log_if_fail "Joined room";

         # Grab the join to use as a prev event
         $join_event_id = $room->get_current_state_event( "m.room.member", $user_id )->{event_id};

         # Make sure client is up to date
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member";
            return unless $event->{sender} eq $user_id;

            Future->done(1);
         });
      })->then( sub {
         log_if_fail "Got join down sync";

         # Let's now block message sends (event B)
         matrix_change_room_power_levels( $creator, $room_id, sub {
            my ( $levels ) = @_;

            $levels->{events}{"m.room.message"} = 50;
         })
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         $power_level_event_id = $body->{event_id};

         # Wait for change to propagate
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.power_levels";

            Future->done(1);
         });
      })->then( sub {
         log_if_fail "Blocked new messages";

         # Now let's send a message (event C), carefully avoiding referencing
         # the new PL event.
         my $event = $room->create_and_insert_event(
            type => "m.room.message",

            prev_events => [ [ $join_event_id, {} ] ],

            sender  => $user_id,
            content => {
               body => "Denied",
            },
         );

         $denied_event_id = $event->{event_id};

         log_if_fail "Sending blocked event", $event;

         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         );
      })->then( sub {
         # Now send a non-message (event D)
         my $event = $room->create_and_insert_event(
            type => "m.room.other_message_type",

            prev_events => [ [ $denied_event_id, {} ], [ $power_level_event_id, {} ] ],

            sender  => $user_id,
            content => {
               body => "Allowed",
            },
         );

         log_if_fail "Sending allowed event", $event;

         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         );
      })->then( sub {
         # Check that we receive D but not C
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            my ( $event ) = @_;

            return unless $event->{sender} eq $user_id;

            $event->{type} eq "m.room.message"
               and die "Message event was not soft failed";

            return unless $event->{type} eq "m.room.other_message_type";

            Future->done(1);
         });
      });
   };
