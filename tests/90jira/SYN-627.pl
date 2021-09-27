test "Events come down the correct room",
   requires => [ local_user_fixture( with_events => 0 ), "can_sync" ],

   # creating all those rooms is quite slow.
   timeout => 100,

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      Future->needs_all( map {
         matrix_create_room( $user )
         ->on_done( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;
         });
      } 1 .. 30 )
      ->then( sub {
         # To ensure that all the creation events have gone through
         matrix_send_room_text_message_synced( $user, $rooms[-1], body => $rooms[-1] );
      })->then( sub {
         matrix_sync( $user );
      })->then( sub {
         Future->needs_all( map {
            my $room_id = $_;

            matrix_send_room_text_message( $user, $room_id, body => "$room_id" );
         } @rooms );
      })->then( sub {
         # Wait until we see all rooms come down the sync stream.
         retry_until_success {
            matrix_sync(
               $user, since => $user->sync_next_batch, update_next_batch => 0
            )->then( sub {
               my ( $body ) = @_;

               foreach my $room_id ( @rooms ) {
                  my $room = $body->{rooms}{join}{$room_id};

                  assert_json_keys( $room, qw( timeline ));
                  @{ $room->{timeline}{events} } == 1 or die "Expected exactly one event";
               }
            })
         }
      })->then( sub {
         matrix_sync_again( $user );
      })->then( sub {
         my ( $body ) = @_;
         my $room_id;

         log_if_fail "sync body", $body;

         foreach $room_id ( @rooms ) {
            my $room = $body->{rooms}{join}{$room_id};

            assert_json_keys( $room, qw( timeline ));
            @{ $room->{timeline}{events} } == 1 or die "Expected exactly one event";

            my $event = $room->{timeline}{events}[0];

            assert_eq( $event->{content}{body}, $room_id, "Event in the wrong room" );
         }

         Future->done(1);
      });
   };
