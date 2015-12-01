test "Sync can be polled for updates",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $next );

      matrix_create_filter( $user, {} )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next = $body->{next_batch};
         Future->needs_all(
            matrix_sync( $user,
               filter => $filter_id, since => $next, timeout => 10000
            ),

            delay( 0.1 )->then( sub {
               matrix_send_room_text_message(
                  $user, $room_id, body => "1"
               )
            }),
         )
      })->then( sub {
         my ( $body, $response, $event_id ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         my $events = $room->{timeline}{events} or
            die "Expected an event timeline";
         @$events == 1 or
            die "Expected one timeline event";

         $room->{timeline}{events}[0]{event_id} eq $event_id
            or die "Unexpected timeline event";

         Future->done(1)
      })
   };
