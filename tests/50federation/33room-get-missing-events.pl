test "Outbound federation can request missing events",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(
                    user_opts => { with_events => 1 },
                    room_opts => { room_version => "1" },
                   ),
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

         # TODO: We happen to know the latest event in the server should be my
         #   m.room.member state event, but that's a bit fragile
         my $latest_event = $room->get_current_state_event( "m.room.member", $user_id );

         # Generate but don't send an event
         $missing_event = $room->create_and_insert_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Message 1",
            },
         );

         # Generate another one and do send it so it will refer to the
         # previous in its prev_events field
         my $sent_event = $room->create_and_insert_event(
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

         Future->needs_all(
            $inbound_server->await_request_get_missing_events( $room_id )
            ->then( sub {
               my ( $req ) = @_;
               my $body = $req->body_from_json;

               assert_json_keys( $body, qw( earliest_events latest_events limit ));
               # TODO: min_depth but I have no idea what it does

               assert_json_list( my $earliest = $body->{earliest_events} );
               @$earliest == 1 or
                  die "Expected a single 'earliest_event' ID";
               assert_eq( $earliest->[0], $latest_event->{event_id},
                  'earliest_events[0]' );

               assert_json_list( my $latest = $body->{latest_events} );
               @$latest == 1 or
                  die "Expected a single 'latest_events' ID";
               assert_eq( $latest->[0], $sent_event->{event_id},
                  'latest_events[0]' );

               my @events = $datastore->get_backfill_events(
                  start_at    => $latest,
                  stop_before => $earliest,
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

foreach my $vis (qw( world_readable shared invite joined )) {
   test "Inbound federation can return missing events for $vis visibility",
      requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                    local_user_and_room_fixtures( room_opts => { room_version => "1" } ),
                    federation_user_id_fixture() ],

      do => sub {
         my ( $outbound_client, $info, $creator, $room_id, $user_id ) = @_;
         my $first_home_server = $info->server_name;

         # start by making the room sekret
         matrix_set_room_history_visibility(
            $creator, $room_id, $vis
         )->then( sub {
            # send a message
            matrix_send_room_text_message( $creator, $room_id, body => "1" )
         })->then( sub {
            $outbound_client->join_room(
               server_name => $first_home_server,
               room_id     => $room_id,
               user_id     => $user_id,
            )
         })->then( sub {
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
               uri      => "/v1/get_missing_events/" . $room->room_id,

               content => {
                  earliest_events => [ $creation_event->{event_id} ],
                  latest_events   => [ $member_event->{event_id} ],
                  limit           => 10,

                  # XXX: min_depth requests the remote server to filter by depth
                  # (it will only return events with depth >= the given value),
                  # but that sounds (a) dangerous and (b) pointless.
                  min_depth       => 1,
               },
            );
         })->then( sub {
            my ( $result ) = @_;
            log_if_fail "get_missing_events result", $result;

            assert_json_keys( $result, qw( events ));
            assert_json_list( my $events = $result->{events} );

            # check that they all look like events
            foreach my $event ( @$events ) {
               assert_is_valid_pdu( $event );
               assert_eq( $event->{room_id}, $room_id,
                          'event room_id' );
            }

            # check that they are the *right* events. We expect copies of:
            # * the creator's join
            # * the power_levels
            # * the join rules
            # * the initial history_vis
            # * another history_vis, unless we tried to set it to the default (shared)
            # * the message

            # if the history vis is 'joined' or 'invite', we should get redacted
            # copies of the events before we joined.
            my $idx = 0;
            assert_eq( $events->[$idx]->{type}, 'm.room.member' );
            assert_eq( $events->[$idx]->{state_key}, $creator->user_id );
            $idx++;

            assert_eq( $events->[$idx]->{type}, 'm.room.power_levels' );
            $idx++;
            assert_eq( $events->[$idx]->{type}, 'm.room.join_rules' );
            $idx++;
            assert_eq( $events->[$idx]->{type}, 'm.room.history_visibility', "event $idx type" );
            $idx++;
            if ( $vis ne 'shared' ) {
               assert_eq( $events->[$idx]->{type}, 'm.room.history_visibility', "event $idx type" );
               $idx++;
            }

            assert_eq( $events->[$idx]->{type}, 'm.room.message', "event $idx type" );
            my $content = $events->[$idx]->{content};
            if ( $vis eq 'joined' || $vis eq 'invited' ) {
               assert_deeply_eq( $content, {}, "redacted event content" );
            } else {
               assert_json_keys( $content, qw( msgtype body ));
            }
            $idx++;

            assert_eq( scalar @$events, $idx, "extra events returned" );

            Future->done(1);
      });
   };
}
