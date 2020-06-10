use Future::Utils qw( repeat );

my $json = JSON->new->convert_blessed(1)->utf8(1);

test "Outbound federation can backfill events",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER, federation_user_id_fixture() ],

   do => sub {
      my ( $user, $inbound_server, $creator_id ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $room_alias = "#50fed-31backfill:$local_server_name";

      my $room = $datastore->create_room(
         creator => $creator_id,
         alias   => $room_alias,
      );
      my $room_id;

      # Create some past messages to backfill from
      $room->create_and_insert_event(
         type => "m.room.message",

         sender  => $creator_id,
         content => {
            msgtype => "m.text",
            body    => "Message $_ here",
         },
      ) for 1 .. 10;

      Future->needs_all(
         $inbound_server->await_request_backfill( $room->room_id )->then( sub {
            my ( $req ) = @_;

            # The helpfully-named 'v' parameter gives the "versions", i.e. the
            # event IDs to start the backfill walk from. This can just be used
            # in the 'start_at' list for $datastore->get_backfill_events.
            # This would typically be an event ID the requesting server is
            # aware exists but has not yet seen, such as one listed in a
            # prev_events or auth_events list.
            my $v     = $req->query_param( 'v' );

            my $limit = $req->query_param( 'limit' );

            my @events = $datastore->get_backfill_events(
               start_at => [ $v ],
               limit    => $limit,
            );

            $req->respond_json( {
               origin           => $inbound_server->server_name,
               origin_server_ts => $inbound_server->time_ms,
               pdus             => \@events,
            } );

            Future->done;
         }),

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/join/$room_alias",

            content => {},
         )->then( sub {
            my ( $body ) = @_;

            $room_id = $body->{room_id};

            # wait for it to arrive
            await_sync_timeline_contains(
               $user, $room_id,
               check => sub {
                  $_[0]->{type} eq "m.room.member"
               },
            );
         })->then( sub {
            # 10 m.room.message events + my own m.room.member
            my $want_count = 11;

            # We may have to get more than once to have all 11 events

            my $token;
            my @events;

            (
               repeat {
                  matrix_get_room_messages( $user, $room_id,
                     limit => $want_count - scalar(@events),
                     from  => $token,
                  )->then( sub {
                     my ( $body ) = @_;
                     push @events, @{ $body->{chunk} };

                     $token = $body->{end};
                     Future->done;
                  });
               } while => sub { !shift->failure and @events < $want_count }
            )->then( sub {
               log_if_fail "Events", \@events;

               assert_json_keys( $events[0], qw( type event_id room_id ));
               assert_eq( $events[0]->{type}, "m.room.member",
                  'events[0] type' );

               my $member_event = shift @events;
               assert_json_keys( $member_event,
                  qw( type event_id room_id sender state_key content ));

               assert_eq( $member_event->{type}, "m.room.member",
                  'member event type' );
               assert_eq( $member_event->{room_id}, $room_id,
                  'member event room_id' );
               assert_eq( $member_event->{sender}, $user->user_id,
                  'member event sender' );
               assert_eq( $member_event->{state_key}, $user->user_id,
                  'member event state_key' );
               assert_eq( $member_event->{content}{membership}, "join",
                  'member event content.membership' );

               foreach my $message ( @events ) {
                  assert_json_keys( $message, qw( type event_id room_id sender ));
                  assert_eq( $message->{type}, "m.room.message",
                     'message type' );
                  assert_eq( $message->{room_id}, $room_id,
                     'message room_id' );
                  assert_eq( $message->{sender}, $creator_id,
                     'message sender' );
               }

               Future->done(1);
            });
         }),
      )
   };

test "Inbound federation can backfill events",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_and_room_fixtures( room_opts => { room_version => "1" } ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $creator->server_name;

      my $local_server_name = $outbound_client->server_name;

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
            uri      => "/v1/backfill/$room_id",

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

test "Backfill checks the events requested belong to the room",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_and_room_fixtures(),
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],
   do => sub {
      my ( $outbound_client, $priv_creator, $priv_room_id,
           $pub_creator, $pub_room_id, $fed_user_id ) = @_;
      my $first_home_server = $priv_creator->server_name;

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
            uri      => "/v1/backfill/$pub_room_id",

            params => {
               v     => $priv_event_id,
               limit => 1,
            },
         );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Backfill response", $body;

         assert_json_keys( $body, qw( origin pdus ));

         assert_eq( $body->{origin}, $first_home_server,
            'body origin' );
         assert_json_list( my $events = $body->{pdus} );

         # the response should be empty.
         assert_eq( 0, scalar @{$body->{pdus}}, 'response should be empty' );
         Future->done(1);
      });
   };

test "Backfilled events whose prev_events are in a different room do not allow cross-room back-pagination",
   requires => [
      federated_rooms_fixture( room_count => 2 ),
      $main::INBOUND_SERVER,
      $main::OUTBOUND_CLIENT,
   ],

   do => sub {
      my ( $creator_user, $sytest_user_id, $room1, $room2, $inbound_server, $outbound_client ) = @_;
      my $synapse_server_name = $creator_user->http->server_name;
      my $room2_id = $room2->room_id;

      # we're going to create four events, P, Q, R, S. P is in room1; Q, R and
      # S are in room2, but Q's auth_events points to P.
      #
      # We send event S over federation, and allow the server to backfill R,
      # leaving the server with a gap in the dag.
      #
      # Then we send P, which is a normal event.
      #
      # Finally we back-paginate, allow Q to land, and make sure that we don't
      # end up seeing P.

      # create the events
      my ( $event_P, $event_id_P ) = $room1->create_and_insert_event(
         type    => "m.room.message",
         sender  => $sytest_user_id,
         content => { body => "event P" },
      );

      my ( $event_Q, $event_id_Q ) = $room2->create_and_insert_event(
         type        => "m.room.message",
         sender      => $sytest_user_id,
         content     => { body => "event Q" },
         prev_events => $room2->make_event_refs( $event_P ),
      );

      my ( $event_R, $event_id_R ) = $room2->create_and_insert_event(
         type        => "m.room.message",
         sender      => $sytest_user_id,
         content     => { body => "event R" },
      );

      my ( $event_S, $event_id_S ) = $room2->create_and_insert_event(
         type        => "m.room.message",
         sender      => $sytest_user_id,
         content     => { body => "event S" },
      );

      log_if_fail "events P, Q, R, S", [ $event_id_P, $event_id_Q, $event_id_R, $event_id_S ];

      Future->needs_all(
         # kick things off by sending S over federation
         $outbound_client->send_event(
            event => $event_S,
            destination => $synapse_server_name,
         ),

         # we expect to get a missing_events request
         $inbound_server->await_request_get_missing_events( $room2_id )
         ->then( sub {
            my ( $req ) = @_;

            my $body = $req->body_from_json;
            log_if_fail "/get_missing_events request", $body;

            assert_deeply_eq(
               $body->{latest_events},
               [ $event_id_S ],
               "latest_events in /get_missing_events request",
            );

            # just return R
            my $resp = { events => [ $event_R ] };

            log_if_fail "/get_missing_events response", $resp;
            $req->respond_json( $resp );
            Future->done(1);
         }),

         # there will still be a gap, so then we expect a state_ids request
         $inbound_server->await_request_state_ids(
            $room2_id, $event_id_Q,
         )->then( sub {
            my ( $req, @params ) = @_;
            log_if_fail "/state_ids request", \@params;

            my %state  = %{ $room2->{current_state} };
            my $resp = {
               pdu_ids => [
                  map { $room2->id_for_event( $_ ) } values( %state ),
               ],

               # XXX we're supposed to return the whole auth chain here,
               # not just Q's auth_events. It doesn't matter too much
               # here though.
               auth_chain_ids => $room2->event_ids_from_refs( $event_Q->{auth_events} ),
            };

            log_if_fail "/state_ids response", $resp;
            $req->respond_json( $resp );
            Future->done(1);
         }),
      )->then( sub {
         # now let's send event P
         $outbound_client->send_event(
            event => $event_P,
            destination => $synapse_server_name,
         );
      })->then( sub {
         # wait for it to arrive
         my $filter = $json->encode( { room => { timeline => { limit => 2 }}} );
         await_sync_timeline_contains(
            $creator_user, $room2_id,
            filter => $filter,
            check => sub {
               $_[0]->{event_id} eq $event_id_S
            },
         );
      })->then( sub {
         my ( $sync_body ) = @_;
         my $room2_sync = $sync_body->{rooms}->{join}->{$room2_id};
         log_if_fail "sync body", $room2_sync;

         my $prev_batch = $room2_sync->{timeline}->{prev_batch};
         assert_ok( $prev_batch, "prev_batch" );

         # now back-paginate, and provide event Q (and P, for good measure) when the
         # server backfills.
         Future->needs_all(
            do_request_json_for(
               $creator_user,
               method => "GET",
               uri    => "/r0/rooms/$room2_id/messages",
               params => {
                  dir  => "b",
                  from => $prev_batch,
               },
            ),

            $inbound_server->await_request_backfill( $room2_id )->then( sub {
               my ( $req ) = @_;

               $req->respond_json( {
                  origin           => $inbound_server->server_name,
                  origin_server_ts => $inbound_server->time_ms,
                  pdus             => [
                     $event_Q,
                     $event_P,
                  ],
               });
               Future->done;
            }),

            # the server will (should) see the prev_event link to P as a hole in the dag,
            # so will send us another state_ids request at Q.
            $inbound_server->await_request_state_ids(
               $room2_id, $event_id_Q,
            )->then( sub {
               my ( $req, @params ) = @_;
               log_if_fail "/state_ids request", \@params;

               my %state  = %{ $room2->{current_state} };
               my $resp = {
                  pdu_ids => [
                     map { $room2->id_for_event( $_ ) } values( %state ),
                  ],
                  auth_chain_ids => $room2->event_ids_from_refs( $event_Q->{auth_events} ),
               };

               log_if_fail "/state_ids response", $resp;
               $req->respond_json( $resp );
               Future->done(1);
             }),
         )->then( sub {
             my ( $messages ) = @_;
             log_if_fail "/messages result", $messages;

             # ensure that P does not feature in the list.
             die 'too few events' if @{$messages->{chunk}} < 2;
             foreach my $ev ( @{$messages->{chunk}} ) {
                if( $ev->{type} eq 'm.room.member' ) {
                   # our join event, so we're ok.
                   last;
                }

                # otherwise it should only be event Q.
                assert_eq( $ev->{type}, 'm.room.message', 'event_type' );
                assert_eq( $ev->{content}->{body}, 'event Q' );
             }
             Future->done;
          });
      });
   };
