# see 31sync/17peeking.pl for local peeking tests

my $room_alias_name = sprintf("peektest-%s", $TEST_RUN_ID);
test "Users can peek into world-readable remote rooms",
   requires => [
      local_user_and_room_fixtures(room_opts => { room_alias_name => $room_alias_name }),
      remote_user_fixture()
   ],

   check => sub {
      my ( $user, $room_id, $peeking_user ) = @_;

      matrix_set_room_history_visibility( $user, $room_id, "world_readable" )->then(sub {
         do_request_json_for( $peeking_user,
            method => "POST",
            uri    => "/r0/peek/#$room_alias_name:".$user->http->server_name,
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

         log_if_fail "sync response", $body;

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

         log_if_fail "next sync response", $body;
         my $room = $body->{rooms}{peek}{$room_id};

         assert_ok( $room->{timeline}->{events}->[-1]->{type} eq 'm.room.message', "second peek has message type" );
         assert_ok( $room->{timeline}->{events}->[-1]->{content}->{body} eq 'something else to peek', "second peek has message body" );

         Future->done(1)
      })
   };

# test "Users can re-peek into world-readable remote rooms"

# test "Users cannot peek into remote rooms with non-world-readable history visibility"

# test "Peeking uses server_name to specify the peeking server"

# test "Peeking into an unknown room returns the right error"

# test "Server implements PUT /peek over federation correctly"

# test "Server implements DELETE /peek over federation correctly"

# test "If a peek is not renewed, the peeked server stops sending events"

# test "Server can't peek into unknown room versions"