use Future::Utils qw( repeat );
use JSON qw( decode_json );

# Tests MSC2753 style peeking

test "Local users can peek into world_readable rooms by room ID",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   check => sub {
      my ( $user, $room_id, $peeking_user ) = @_;

      matrix_set_room_history_visibility( $user, $room_id, "world_readable" )->then(sub {
         do_request_json_for( $peeking_user,
            method => "POST",
            uri    => "/r0/peek/$room_id",
            content => {},
         )
      })->then( sub {
         matrix_send_room_text_message_synced( $user, $room_id, body => "something to peek");
      })->then(sub {
         await_sync( $peeking_user,
            since => $peeking_user->sync_next_batch,
            check => sub {
               my ( $body ) = @_;
               return 0 unless $body->{rooms}{peek}{$room_id};
               return $body;
            }
         )
      })->then( sub {
         my ( $body ) = @_;
         $peeking_user->sync_next_batch = $body->{next_batch};

         log_if_fail "first sync response", $body;

         my $room = $body->{rooms}{peek}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         assert_json_keys( $room->{state}, qw( events ));
         assert_json_keys( $room->{ephemeral}, qw( events ));

         assert_ok( $room->{timeline}->{events}->[0]->{type} eq 'm.room.create', "peek has m.room.create" );
         assert_ok( $room->{timeline}->{events}->[-1]->{type} eq 'm.room.message', "peek has message type" );
         assert_ok( $room->{timeline}->{events}->[-1]->{content}->{body} eq 'something to peek', "peek has message body" );
         assert_ok( @{$room->{state}->{events}} == 0 );

         assert_ok( scalar keys(%{$body->{rooms}{join}}) == 0, "no joined rooms present");

         matrix_sync_again( $peeking_user );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "second sync response", $body;
         my $room = $body->{rooms}{peek}{$room_id};
         (!defined $room) or die "Unchanged rooms shouldn't be in the sync response";
      })->then( sub {
         matrix_send_room_text_message_synced( $user, $room_id, body => "something else to peek");
      })->then( sub {
         await_sync( $peeking_user,
            since => $peeking_user->sync_next_batch,
            check => sub {
               my ( $body ) = @_;
               return 0 unless $body->{rooms}{peek}{$room_id};
               return $body;
            }
         )
      })->then( sub {
         my ( $body ) = @_;
         $peeking_user->sync_next_batch = $body->{next_batch};

         log_if_fail "third sync response", $body;
         my $room = $body->{rooms}{peek}{$room_id};

         assert_ok( $room->{timeline}->{events}->[-1]->{type} eq 'm.room.message', "second peek has message type" );
         assert_ok( $room->{timeline}->{events}->[-1]->{content}->{body} eq 'something else to peek', "second peek has message body" );

         Future->done(1)
      })
   };


for my $visibility (qw(shared invited joined)) {
   test "We can't peek into rooms with $visibility history_visibility",
      requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

      check => sub {
         my ( $user, $room_id, $peeking_user ) = @_;

         matrix_set_room_history_visibility( $user, $room_id, $visibility )->then(sub {
            do_request_json_for( $peeking_user,
               method => "POST",
               uri    => "/r0/peek/$room_id",
               content => {},
            );
         })->main::expect_http_403()
         ->then( sub {
            my ( $response ) = @_;
            my $body = decode_json( $response->content );
            log_if_fail "error body", $body;
            assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );
            Future->done( 1 );
         });
      };
}


my $room_alias_name = sprintf("peektest-%s", $TEST_RUN_ID);
test "Local users can peek by room alias",
   requires => [
      local_user_and_room_fixtures(room_opts => { room_alias_name => $room_alias_name }),
      local_user_fixture()
   ],

   check => sub {
      my ( $user, $room_id, $peeking_user ) = @_;

      matrix_set_room_history_visibility( $user, $room_id, "world_readable" )->then(sub {
         do_request_json_for( $peeking_user,
            method => "POST",
            uri    => "/r0/peek/#$room_alias_name:".$user->http->server_name,
            content => {},
         )
      })->then(sub {
         matrix_send_room_text_message_synced( $user, $room_id, body => "something to peek");
      })->then(sub {
         await_sync( $peeking_user,
            since => $peeking_user->sync_next_batch,
            check => sub {
               my ( $body ) = @_;
               return 0 unless $body->{rooms}{peek}{$room_id};
               return $body;
            }
         )
      })->then( sub {
         my ( $body ) = @_;
         $peeking_user->sync_next_batch = $body->{next_batch};

         log_if_fail "first sync response", $body;

         my $room = $body->{rooms}{peek}{$room_id};
         assert_ok( $room->{timeline}->{events}->[-1]->{content}->{body} eq 'something to peek', "peek has message body" );
         Future->done(1)
      })
   };

test "Peeked rooms only turn up in the sync for the device who peeked them",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   check => sub {
      my ( $user, $room_id, $peeking_user ) = @_;
      my ( $peeking_user_device2 );

      matrix_set_room_history_visibility( $user, $room_id, "world_readable" )->then(sub {
         matrix_login_again_with_user($peeking_user);
      })->then(sub {
         $peeking_user_device2 = $_[0];
         do_request_json_for( $peeking_user,
            method => "POST",
            uri    => "/r0/peek/$room_id",
            content => {},
         )
      })->then(sub {
         matrix_send_room_text_message_synced( $user, $room_id, body => "something to peek");
      })->then(sub {
         await_sync( $peeking_user,
            since => $peeking_user->sync_next_batch,
            check => sub {
               my ( $body ) = @_;
               return 0 unless $body->{rooms}{peek}{$room_id};
               return $body;
            }
         )
      })->then( sub {
         my ( $body ) = @_;
         $peeking_user->sync_next_batch = $body->{next_batch};
         log_if_fail "device 1 first sync response", $body;
         my $room = $body->{rooms}{peek}{$room_id};
         assert_ok( $room->{timeline}->{events}->[-1]->{content}->{body} eq 'something to peek', "peek has message body" );
      })->then(sub {
         # FIXME: racey - this may return blank due to the peek not having taken effect yet
         matrix_sync( $peeking_user_device2, timeout => 1000 * $TIMEOUT_FACTOR );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "device 2 first sync response", $body;
         assert_ok( scalar keys(%{$body->{rooms}{peek}}) == 0, "no peeked rooms present");
      })->then( sub {
         matrix_send_room_text_message_synced( $user, $room_id, body => "something else to peek")
      })->then( sub {
         await_sync( $peeking_user,
            since => $peeking_user->sync_next_batch,
            check => sub {
               my ( $body ) = @_;
               return 0 unless $body->{rooms}{peek}{$room_id};
               return $body;
            }
         )
      })->then( sub {
         my ( $body ) = @_;
         $peeking_user->sync_next_batch = $body->{next_batch};
         log_if_fail "device 1 second sync response", $body;
         my $room = $body->{rooms}{peek}{$room_id};
         assert_ok( $room->{timeline}->{events}->[-1]->{content}->{body} eq 'something else to peek', "second peek has message body" );
         # FIXME: racey - this may return blank due to the peek not having taken effect yet
         matrix_sync_again( $peeking_user_device2, timeout => 1000 * $TIMEOUT_FACTOR );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "device 2 second sync response", $body;
         assert_ok( scalar keys(%{$body->{rooms}{peek}}) == 0, "still no peeked rooms present");
         Future->done(1)
      })
   };

# test "Users can unpeek from rooms"

# test "Users can peek, unpeek and peek again"

# test "Peeking with full_state=true does the right thing"

# test "Joining a peeked room moves it atomically from peeked to joined rooms and stops peeking"

# test "Parting a room which was joined after being peeked doesn't go back to being peeked"

# test "Changing history visibility to non-world_readable terminates peeks"
