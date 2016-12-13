test "/joined_rooms returns only joined rooms",
   requires => [ local_user_fixture(), local_user_fixture(), ],

   do => sub {
      my ( $user1, $user2 ) = @_;

      my ( $room1, $room2, $room3 );

      matrix_create_room( $user1 )->then( sub {
         ( $room1 ) = @_;

         log_if_fail "room 1", $room1;

         matrix_create_room( $user1 );
      })->then( sub {
         ( $room2 ) = @_;

         log_if_fail "room 2", $room2;

         matrix_leave_room( $user1, $room2 );
      })->then( sub {
         matrix_create_room( $user2 );
      })->then( sub {
         ( $room3 ) = @_;

         log_if_fail "room 3", $room3;

         matrix_invite_user_to_room( $user2, $user1, $room3 );
      })->then( sub {
         do_request_json_for( $user1,
            method => "GET",
            uri => "/unstable/joined_rooms",
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( joined_rooms ) );
         assert_json_list( my $joined_rooms = $body->{joined_rooms});

         assert_eq( scalar @$joined_rooms, 1, "expected only 1 room" );
         assert_eq( $joined_rooms->[0], $room1, "wrong room returned" );

         Future->done( 1 );
      });
   };


test "/joined_members return joined members",
   requires => [ local_user_fixtures( 3 ) ],

   do => sub {
      my ( $user1, $user2, $user3 ) = @_;

      my $room_id;

      my $user_id1 = $user1->user_id;
      my $display_name = "Display Name";
      my $avatar_url = "http://example.com/avatar.png";

      Future->needs_all(
         do_request_json_for( $user1,
            method  => "PUT",
            uri     => "/r0/profile/$user_id1/displayname",
            content => {
               displayname => $display_name,
            },
         ),
         do_request_json_for( $user1,
            method  => "PUT",
            uri     => "/r0/profile/$user_id1/avatar_url",
            content => {
               avatar_url => $avatar_url,
            },
         )
      )->then( sub {
         matrix_create_room( $user1,
            invite => [ $user2->user_id, $user3->user_id ],
         )
      })->then( sub {
         ( $room_id ) = @_;

         log_if_fail "room", $room_id;

         matrix_join_room( $user2, $room_id )
      })->then( sub {
         matrix_leave_room( $user2, $room_id )
      })->then( sub {
         do_request_json_for( $user1,
            method => "GET",
            uri => "/unstable/rooms/$room_id/joined_members",
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_deeply_eq( $body, {
            joined => {
               $user1->user_id => {
                  display_name => $display_name,
                  avatar_url => $avatar_url,
               }
            }
         } );

         Future->done( 1 );
      })
   };
