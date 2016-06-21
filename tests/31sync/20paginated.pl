use Future::Utils qw( repeat );

test "Can ask for paginated sync",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_sync_post( $user,
         content => {
            pagination_config => {
               limit => 10,
               order => "o",
            }
         }
      );
   };

multi_test "Paginated sync",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      repeat( sub {
         matrix_create_room_synced( $user )
         ->then( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "First message",
            )
         });
      }, foreach => [ 0 .. 10 ])
      ->then( sub {
         matrix_sync_post( $user,
            content => {
               pagination_config => {
                  limit => 5,
                  order => "o",
               }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );

         assert_eq( scalar keys $body->{rooms}{join}, 5, "correct number of rooms");
         $body->{pagination_info}{limited} or die "Limited flag is not set";
         not exists ($body->{rooms}{join}{$rooms[0]}) or die "Unexpected room";

         pass "Correct initial sync response";

         matrix_send_room_text_message_synced( $user, $rooms[0],
            body => "Second message",
         )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );

         assert_eq( scalar keys $body->{rooms}{join}, 1, "correct number of rooms");
         not $body->{pagination_info}{limited} or die "Limited flag is set";
         exists ($body->{rooms}{join}{$rooms[0]}) or die "Room is not in entry";

         pass "Unseen room is in incremental sync";

         my $room = $body->{rooms}{join}{$rooms[0]};

         first {
            $_->{content}{body} eq "Second message"
         } @{$room->{timeline}{events}} or die "Expected new message";

         assert_eq( $room->{timeline}{limited}, JSON::true, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 2, "two messages in timeline");

         pass "Got some historic data in newly seen room";

         first {
            $_->{type} eq "m.room.create"
         } @{$room->{state}{events}} or die "Expected creation event";

         pass "Got full state";

         matrix_send_room_text_message_synced( $user, $rooms[0],
            body => "Third message",
         )
      })->then(sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_eq( scalar keys $body->{rooms}{join}, 1, "correct number of rooms");
         not $body->{pagination_info}{limited} or die "Limited flag is set";
         exists ($body->{rooms}{join}{$rooms[0]}) or die "Room is not in entry";

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{timeline}{limited}, JSON::false, "room is not limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 1, "one new messages in timeline");
         assert_eq( scalar @{$room->{state}{events}}, 0, "no new state");

         pass "Previously seen rooms do not have state.";

         Future->done( 1 );
      });
   };
