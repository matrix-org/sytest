test "Inbound federation correctly soft fails events",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER,
                 local_user_and_room_fixtures(
                    user_opts => { with_events => 1 },
                    room_opts => { room_version => "1" },
                 ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $creator->server_name;

      my $room;

      # We'll grab out some events to use as prev events
      my $join_event;
      my $power_level_event_id;
      my $denied_event;

      my @remote_auth_events;

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
      #  D = remote user sends a non-message event
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
         $join_event = $room->get_current_state_event( "m.room.member", $user_id );

         # Make sure client is up to date
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member";
            return unless $event->{sender} eq $user_id;

            return 1;
         });
      })->then( sub {
         log_if_fail "Got join down sync";

         # before we change the state of the room, stash enough of the
         # current state that we can build events on another branch of
         # the DAG.
         @remote_auth_events = (
            $room->get_current_state_event( "m.room.create" ),
            $room->get_current_state_event( "m.room.join_rules" ),
            $room->get_current_state_event( "m.room.power_levels" ),
            $join_event,
         );

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

            return 1;
         });
      })->then( sub {
         log_if_fail "Blocked new messages";

         # Now let's send a message (event C), carefully avoiding referencing
         # the new PL event.
         $denied_event = $room->create_and_insert_event(
            type => "m.room.message",

            auth_events => $room->make_event_refs( @remote_auth_events ),
            prev_events => $room->make_event_refs( $join_event ),

            sender  => $user_id,
            content => {
               body => "Denied",
            },
         );

         log_if_fail "Sending blocked event ".$room->id_for_event( $denied_event ),
            $denied_event;

         $outbound_client->send_event(
            event => $denied_event,
            destination => $first_home_server,
         );
      })->then( sub {
         # Now send a non-message (event D)
         my $pl_event = $inbound_server->datastore->get_event( $power_level_event_id );
         die "did not receive PL event" unless $pl_event;
         my $event = $room->create_and_insert_event(
            type => "m.room.other_message_type",

            prev_events => $room->make_event_refs( $denied_event, $pl_event ),

            sender  => $user_id,
            content => {
               body => "Allowed",
            },
         );

         log_if_fail "Sending allowed event ".$room->id_for_event( $event ),
            $event;

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

            return 1;
         });
      });
   };


test "Inbound federation accepts a second soft-failed event",
   # this is mostly a regression test for https://github.com/matrix-org/synapse/issues/5090.
   requires => [
      $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER,
      local_user_and_room_fixtures(
         user_opts => { with_events => 1 },
         room_opts => { room_version => "1" }
      ),
      federation_user_id_fixture(),
   ],

   do => sub {
      my (
         $outbound_client, $inbound_server, $creator, $room_id,
         $remote_user_id,
      ) = @_;
      my $first_home_server = $creator->server_name;

      my $room;

      # We're going to construct a room graph like:
      #
      #        J1
      #       /  \
      #      /    \
      #    PL1     M1
      #     |    / |  \
      #     |   /  SF1 SF2
      #     |  /
      #      M3
      #
      # Where time is flowing downwards.
      #
      #  J1  = join of remote user
      #  PL1 = creator of room blocks SF event sending
      #  M1  = remote user sends a permitted message
      #  SF1, SF2 = remote user sends a soft-failed message
      #  M3  = creator sends a message
      #
      # Since the banning of SF events happens before SF1 and SF2, we expect the
      # local server to soft fail SF1 and SF2 when they are received.
      #
      # We should therefore end up with PL1 and M1 as the forward-extremities of
      # the room, and hence the prev_events of M3.
      #
      # (The effect of #5090 was that M1 was incorrectly excluded from the
      # forward-extremities.)

      my $join_event;
      my $event_id_pl1;
      my $event_m1;
      my $event_sf1;
      my $event_sf2;

      my @remote_auth_events;

      # First we join the room (event J1)
      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $remote_user_id,
      )->then( sub {
         ( $room ) = @_;

         log_if_fail "Joined room";

         # Grab the join to use as a prev event
         $join_event = $room->get_current_state_event( "m.room.member", $remote_user_id );

         # Make sure client is up to date
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member";
            return unless $event->{sender} eq $remote_user_id;

            return 1;
         });
      })->then( sub {
         log_if_fail "Got join down sync";

         # before we change the state of the room, stash enough of the
         # current state that we can build events on another branch of
         # the DAG.
         @remote_auth_events = (
            $room->get_current_state_event( "m.room.create" ),
            $room->get_current_state_event( "m.room.join_rules" ),
            $room->get_current_state_event( "m.room.power_levels" ),
            $join_event,
         );

         # Let's now block sf message sends (event PL1)
         matrix_change_room_power_levels( $creator, $room_id, sub {
            my ( $levels ) = @_;

            $levels->{events}{"test.sf"} = 50;
         })
      })->then( sub {
         my ( $body ) = @_;

         $event_id_pl1 = $body->{event_id};

         # Wait for change to propagate
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.power_levels";

            return 1;
         });
      })->then( sub {
         log_if_fail "Blocked new SF events";

         # send a regular message (event m1), which should be accepted
         $event_m1 = $room->create_and_insert_event(
            event_id_suffix => "m1",
            auth_events => $room->make_event_refs( @remote_auth_events ),
            prev_events => $room->make_event_refs( $join_event ),
            sender  => $remote_user_id,
            type => "m.room.message",
            content => { body => "M1" },
         );

         log_if_fail "Sending M1 ".$room->id_for_event( $event_m1 ),
            $event_m1;

         $outbound_client->send_event(
            event => $event_m1,
            destination => $first_home_server,
         );
      })->then( sub {
         # send an event which will be soft-failed (sf1)
         $event_sf1 = $room->create_and_insert_event(
            event_id_suffix => "sf1",
            auth_events => $room->make_event_refs( @remote_auth_events ),
            prev_events => $room->make_event_refs( $event_m1 ),
            sender  => $remote_user_id,
            type => "test.sf",
            content => { body => "SF1" },
         );

         log_if_fail "Sending blocked event 1 ".$room->id_for_event( $event_sf1 ),
            $event_sf1;

         $outbound_client->send_event(
            event => $event_sf1,
            destination => $first_home_server,
         );
      })->then( sub {
         # send a second soft-fail event
         $event_sf2 = $room->create_and_insert_event(
            event_id_suffix => "sf2",
            auth_events => $room->make_event_refs( @remote_auth_events ),
            prev_events => $room->make_event_refs( $event_m1 ),
            sender  => $remote_user_id,
            type => "test.sf",
            content => { body => "SF2" },
         );

         log_if_fail "Sending blocked event 2 ".$room->id_for_event( $event_sf2 ),
            $event_sf2;

         $outbound_client->send_event(
            event => $event_sf2,
            destination => $first_home_server,
         );
      })->then( sub {
         # make sure that at least M1 has propagated
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            return $_[0]->{event_id} eq $room->id_for_event( $event_m1 );
         });
      })->then( sub {
         # now tell synapse to send a regular message, and check it
         Future->needs_all(
            matrix_send_room_text_message( $creator, $room_id, body => "m3" ),

            $inbound_server->await_event( "m.room.message", $room_id, sub {1} )
            ->then( sub {
               my ( $event ) = @_;
               log_if_fail "Received event", $event;
               assert_eq( $event->{content}{body}, "m3", "event content body" );

               my $prev_event_ids = $room->event_ids_from_refs( $event->{prev_events} );
               log_if_fail "Received prev_event_ids", $prev_event_ids;
               assert_elements_eq(
                  $prev_event_ids,
                  [ $event_id_pl1, $room->id_for_event( $event_m1 ) ],
                  "prev_event ids",
               );

               Future->done(1);
            }),
         );
      });
   };


test "Inbound federation correctly handles soft failed events as extremities",
   # this is mostly a regression test for https://github.com/matrix-org/synapse/issues/5269.
   requires => [
      $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER,
      local_user_and_room_fixtures(
         user_opts => { with_events => 1 },
          room_opts => { room_version => "1" },
      ),
      federation_user_id_fixture(),
   ],

   do => sub {
      my (
         $outbound_client, $inbound_server, $creator, $room_id,
         $remote_user_id,
      ) = @_;
      my $first_home_server = $creator->server_name;

      my $room;

      # We're going to construct a room graph like:
      #
      #        J1
      #       /  \
      #      /    \
      #    PL1     M1
      #     |      |
      #     |     SF1
      #     |      |
      #      \    SF2
      #       \   /
      #         M2
      #         |
      #         M3
      #
      # Where time is flowing downwards.
      #
      #  J1  = join of remote user
      #  PL1 = creator of room blocks SF event sending
      #  M1  = remote user sends a permitted message
      #  SF1 = remote user sends a soft-failed message
      #  SF2 = remote user sends a soft-failed message
      #  M2  = remote user sends a permitted message
      #  M3  = creator sends a message
      #
      # Since the banning of SF events happens before SF1 and SF2, we expect the
      # local server to soft fail SF1 and SF2 when they are received.
      #
      # M1 and PL1 will therefore become forward-extremities of the room. However, M2 will
      # be accepted, and replace M1 and PL1 as the extremities of the room. M2 should
      # therefore be the sole prev_event of M3.
      #
      # (The effect of #5269 was that M1 was incorrectly included as a
      # forward-extremity.)

      my $join_event;
      my $event_id_pl1;
      my $event_m1;
      my $event_sf1;
      my $event_sf2;
      my $event_m2;

      my @remote_auth_events;

      # First we join the room (event J1)
      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $remote_user_id,
      )->then( sub {
         ( $room ) = @_;

         log_if_fail "Joined room";

         # Grab the join to use as a prev event
         $join_event = $room->get_current_state_event( "m.room.member", $remote_user_id );

         # Make sure client is up to date
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member";
            return unless $event->{sender} eq $remote_user_id;

            return 1;
         });
      })->then( sub {
         log_if_fail "Got join down sync";

         # before we change the state of the room, stash enough of the
         # current state that we can build events on another branch of
         # the DAG.
         @remote_auth_events = (
            $room->get_current_state_event( "m.room.create" ),
            $room->get_current_state_event( "m.room.join_rules" ),
            $room->get_current_state_event( "m.room.power_levels" ),
            $join_event,
         );

         # Let's now block sf message sends (event PL1)
         matrix_change_room_power_levels( $creator, $room_id, sub {
            my ( $levels ) = @_;

            $levels->{events}{"test.sf"} = 50;
         })
      })->then( sub {
         my ( $body ) = @_;

         $event_id_pl1 = $body->{event_id};
         log_if_fail "Blocked new SF events with PL event $event_id_pl1";

         # Wait for change to propagate
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.power_levels";

            return 1;
         });
      })->then( sub {
         # send a regular message (event m1), which should be accepted
         $event_m1 = $room->create_and_insert_event(
            event_id_suffix => "m1",
            prev_events => $room->make_event_refs( $join_event ),
            auth_events => $room->make_event_refs( @remote_auth_events ),
            sender  => $remote_user_id,
            type => "m.room.message",
            content => { body => "M1" },
         );

         log_if_fail "Sending valid message M1 ".$room->id_for_event( $event_m1 ),
            $event_m1;

         $outbound_client->send_event(
            event => $event_m1,
            destination => $first_home_server,
         );
      })->then( sub {
         # send an event which will be soft-failed (sf1)
         $event_sf1 = $room->create_and_insert_event(
            event_id_suffix => "sf1",
            prev_events => $room->make_event_refs( $event_m1 ),
            auth_events => $room->make_event_refs( @remote_auth_events ),
            sender  => $remote_user_id,
            type => "test.sf",
            content => { body => "SF1" },
         );

         log_if_fail "Sending blocked event 1 ".$room->id_for_event( $event_sf1 ),
            $event_sf1;

         $outbound_client->send_event(
            event => $event_sf1,
            destination => $first_home_server,
         );
      })->then( sub {
         # send another event which will be soft-failed (sf2)
         $event_sf2 = $room->create_and_insert_event(
            event_id_suffix => "sf2",
            prev_events => $room->make_event_refs( $event_sf1 ),
            auth_events => $room->make_event_refs( @remote_auth_events ),
            sender  => $remote_user_id,
            type => "test.sf",
            content => { body => "SF2" },
         );

         log_if_fail "Sending blocked event 2 ".$room->id_for_event( $event_sf2 ),
            $event_sf2;

         $outbound_client->send_event(
            event => $event_sf2,
            destination => $first_home_server,
         );
      })->then( sub {
         # send a regular message (event m2), which should be accepted
         my $event_pl1 = $inbound_server->datastore->get_event( $event_id_pl1 );
         $event_m2 = $room->create_and_insert_event(
            event_id_suffix => "m2",
            prev_events => $room->make_event_refs( $event_pl1, $event_sf2 ),
            sender  => $remote_user_id,
            type => "m.room.message",
            content => { body => "M2" },
         );

         log_if_fail "Sending new valid M2 event ".$room->id_for_event( $event_m2 ),
            $event_m2;

         $outbound_client->send_event(
            event => $event_m2,
            destination => $first_home_server,
         );
      })->then( sub {
         log_if_fail "Waiting for M2 to propagate to server under test";
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            return $_[0]->{event_id} eq $room->id_for_event( $event_m2 );
         });
      })->then( sub {
         # now tell synapse to send a regular message, and check it
         Future->needs_all(
            matrix_send_room_text_message( $creator, $room_id, body => "m3" ),

            $inbound_server->await_event( "m.room.message", $room_id, sub {1} )
            ->then( sub {
               my ( $event ) = @_;
               log_if_fail "Received event", $event;
               assert_eq( $event->{content}{body}, "m3", "event content body" );
               my $prev_event_ids = $room->event_ids_from_refs( $event->{prev_events} );
               log_if_fail "Received prev_event_ids", $prev_event_ids;
               assert_elements_eq(
                  $prev_event_ids, [ $room->id_for_event( $event_m2 ) ], "prev_event ids",
               );
               Future->done(1);
            }),
         );
      });
   };
