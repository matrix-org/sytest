use Time::HiRes qw( time );
use Protocol::Matrix qw( redact_event );


test "Outbound federation can send events",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER, federation_user_id_fixture() ],

   do => sub {
      my ( $user, $inbound_server, $creator_id ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $room_alias = "#50fed-31send:$local_server_name";

      my $room = $datastore->create_room(
         creator => $creator_id,
         alias   => $room_alias,
      );

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/join/$room_alias",

         content => {},
      )->then( sub {
         my ( $body ) = @_;

         my $room_id = $body->{room_id};

         Future->needs_all(
            $inbound_server->await_event( "m.room.message", $room_id, sub {1} )
            ->then( sub {
               my ( $event ) = @_;
               log_if_fail "Received event", $event;

               assert_eq( $event->{sender}, $user->user_id,
                  'event sender' );
               assert_eq( $event->{content}{body}, "Hello",
                  'event content body' );

               Future->done(1);
            }),

            matrix_send_room_text_message( $user, $room_id, body => "Hello" ),
         );
      });
   };

test "Inbound federation can receive events",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_and_room_fixtures(
                   user_opts => { with_events => 1 },
                 ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $creator->server_name;

      my $local_server_name = $outbound_client->server_name;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         my ( $room ) = @_;

         my $event = $room->create_and_insert_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Hello",
            },
         );

         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         );
      })->then( sub {
         await_event_for( $creator, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{room_id} eq $room_id;

            assert_eq( $event->{sender}, $user_id,
               'event sender' );
            assert_eq( $event->{content}{body}, "Hello",
               'event content body' );

            Future->done(1);
         });
      });
   };

test "Inbound federation can receive redacted events",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_and_room_fixtures(
                   user_opts => { with_events => 1 },
                 ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $creator->server_name;

      my $local_server_name = $outbound_client->server_name;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         my ( $room ) = @_;

         my $event = $room->create_and_insert_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Hello",
            },
         );

         redact_event( $event );

         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         );
      })->then( sub {
         await_event_for( $creator, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{room_id} eq $room_id;

            assert_eq( $event->{sender}, $user_id,
               'event sender' );
            assert_deeply_eq( $event->{content}, {},
               'event content body' );

            Future->done(1);
         });
      });
   };

# Test for MSC2228 for messages received through federation.
test "Ephemeral messages received from servers are correctly expired",
   requires => [ local_user_and_room_fixtures(), remote_user_fixture() ],

   do => sub {
      my ( $local_user, $room_id, $federated_user ) = @_;

      my $filter = '{"types":["m.room.message"]}';

      matrix_invite_user_to_room( $local_user, $federated_user, $room_id )->then( sub {
         matrix_join_room( $federated_user, $room_id )
      })->then( sub {
         my $now_ms = int( time() * 1000 );

         matrix_send_room_message( $local_user, $room_id,
            content => {
               msgtype                          => "m.text",
               body                             => "This is a message",
               "org.matrix.self_destruct_after" => $now_ms + 1000,
            },
         )
      })->then( sub {
         await_sync_timeline_contains($local_user, $room_id, check => sub {
            my ($event) = @_;
            return $event->{content}{body} eq "This is a message"
         })
      })->then( sub {
         # wait for the message to expire
         delay( 1.5 )
      })->then( sub {
         my $iter = 0;
         retry_until_success {
            matrix_get_room_messages( $local_user, $room_id, filter => $filter )->then( sub {
               $iter++;
               my ( $body ) = @_;
               log_if_fail "Iteration $iter: response body after expiry", $body;

               my $chunk = $body->{chunk};

               @$chunk == 1 or
                  die "Expected 1 message";

               # Check that we can't read the message's content after its expiry.
               assert_deeply_eq( $chunk->[0]{content}, {}, 'chunk[0] content size' );

               Future->done(1);
            })->on_fail( sub {
               my ( $exc ) = @_;
               chomp $exc;
               log_if_fail "Iteration $iter: not ready yet: $exc";
            });
         }
      });
   };
