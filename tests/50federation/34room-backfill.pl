use Future::Utils qw( repeat );

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

      # Create some past messages to backfill from
      $room->create_event(
         type => "m.room.message",

         sender  => $creator_id,
         content => {
            msgtype => "m.text",
            body    => "Message $_ here",
         },
      ) for 1 .. 10;

      Future->needs_all(
         $inbound_server->await_backfill( $room->room_id )->then( sub {
            my ( $req ) = @_;

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
            uri    => "/api/v1/join/$room_alias",

            content => {},
         )->then( sub {
            my ( $body ) = @_;

            my $room_id = $body->{room_id};

            # 10 m.room.message events + my own m.room.member
            my $want_count = 11;

            # We may have to get more than once to have all 11 events

            my $token;
            my @events;
            ( repeat {
               matrix_get_room_messages( $user, $room_id,
                  limit => $want_count - scalar(@events),
                  from  => $token,
               )->then( sub {
                  my ( $body ) = @_;
                  push @events, @{ $body->{chunk} };

                  $token = $body->{end};
                  Future->done;
               });
            } while => sub { !shift->failure and @events < $want_count } )->then( sub {
               log_if_fail "Events", \@events;

               assert_json_keys( $events[0], qw( type event_id room_id ));
               assert_eq( $events[0]->{type}, "m.room.member",
                  'events[0] type' );

               my $member_event = shift @events;
               # TODO: assert on its fields

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
