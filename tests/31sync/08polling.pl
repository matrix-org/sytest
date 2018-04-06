test "Sync can be polled for updates",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      matrix_create_filter( $user, {
         presence => { not_types => ["m.presence"] }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         Future->needs_all(
            matrix_sync_again( $user, filter => $filter_id, timeout => 10000 ),

            delay( 0.1 )->then( sub {
               matrix_send_room_text_message(
                  $user, $room_id, body => "1"
               )
            }),
         )
      })->then( sub {
         my ( $body, $response, $event_id ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         log_if_fail "Sync entry", $room;

         my $events = $room->{timeline}{events} or
            die "Expected an event timeline";
         @$events == 1 or
            die "Expected one timeline event";

         $room->{timeline}{events}[0]{event_id} eq $event_id
            or die "Unexpected timeline event";

         Future->done(1)
      })
   };

test "Sync is woken up for leaves",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      matrix_create_filter( $user, {
         presence => { not_types => ["m.presence"] }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         Future->needs_all(
            matrix_sync_again( $user, filter => $filter_id, timeout => 10000 ),

            delay( 0.1 )->then( sub {
               matrix_leave_room(
                  $user, $room_id
               )
            }),
         )
      })->then( sub {
         my ( $body, $response, $event_id ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};

         my $events = $room->{timeline}{events} or
            die "Expected an event timeline";
         @$events == 1 or
            die "Expected one timeline event";

         Future->done(1)
      })
   };
