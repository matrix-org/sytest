use Future::Utils qw( repeat );

# Tests MSC2753 style peeking

test "Local users can peek by room ID",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   check => sub {
      my ( $user, $room_id, $peeking_user ) = @_;

      matrix_send_room_text_message_synced( $user, $room_id, body => "something to peek")->then(sub {
         do_request_json_for( $peeking_user,
            method => "POST",
            uri    => "/r0/peek/$room_id",
            content => {},
         )
      })->then(sub {
         matrix_sync( $peeking_user );
      })->then( sub {
         my ( $body ) = @_;

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
         matrix_send_room_text_message_synced( $user, $room_id, body => "something else to peek")
      })->then( sub {
         matrix_sync_again( $peeking_user );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "third sync response", $body;
         my $room = $body->{rooms}{peek}{$room_id};

         assert_ok( $room->{timeline}->{events}->[-1]->{type} eq 'm.room.message', "second peek has message type" );
         assert_ok( $room->{timeline}->{events}->[-1]->{content}->{body} eq 'something else to peek', "second peek has message body" );

         Future->done(1)
      })
   };

# test "Local users can peek by room alias",

# test "Peeked rooms only turn up in the sync for the device who peeked them"

# test "Users can unpeek from rooms"

# test "Joining a peeked room moves it atomically from peeked to joined rooms and stops peeking",

# test "Parting a room which was joined after being peeked"
