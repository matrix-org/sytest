test "Read markers appear in incremental v2 /sync",
   requires => [ local_user_fixture(), qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $room_id, $event_id );

      matrix_create_room( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "hello" );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_advance_room_read_marker_synced( $user, $room_id, $event_id );
      })->then_done(1);
   };


test "Read markers appear in initial v2 /sync",
   requires => [ local_user_fixture(), qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $room_id, $event_id );

      matrix_create_room( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "hello" );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_advance_room_read_marker_synced( $user, $room_id, $event_id );
      })->then( sub {
         matrix_sync( $user );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         my $account_data = $room->{account_data}{events};

         @{ $account_data } == 1 or die "Expected a m.fully_read event";

         log_if_fail "Account data:", $account_data;

         my $read_marker = $account_data->[0];

         $read_marker->{type} eq "m.fully_read" or die "Unexpected event type";
         $read_marker->{content}{event_id} eq $event_id
            or die "Expected to see a marker for $event_id";

         Future->done(1);
      });
   };


test "Read markers can be updated",
   requires => [ local_user_fixture(), qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $room_id, $event_id );

      matrix_create_room( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "hello" );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_advance_room_read_marker_synced( $user, $room_id, $event_id );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id, body => "hello2" );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_advance_room_read_marker_synced( $user, $room_id, $event_id );
      })->then_done(1);
   };
