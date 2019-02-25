test "User in shared private room does appear in user directory",
   requires => [ local_user_fixtures( 2 ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my $room_id;

      my $displayname = generate_random_displayname();

      matrix_set_displayname( $user1, $displayname )
      ->then( sub {
         matrix_create_room( $user1,
            preset => "private_chat", invite => [ $user2->user_id ],
         );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room_synced( $user2, $room_id );
      })->then( sub {
         matrix_get_user_dir_synced( $user2, $displayname );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         any { $_->{user_id} eq $user1->user_id } @{ $body->{results} }
            or die "user not in list";

         Future->done( 1 );
      });
   };


test "User in shared private room does appear in user directory until leave",
   requires => [ local_user_fixtures( 2 ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my $room_id;

      my $displayname = generate_random_displayname();

      matrix_set_displayname( $user1, $displayname )
      ->then( sub {
         matrix_create_room( $user1,
            preset => "private_chat", invite => [ $user2->user_id ],
         );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room_synced( $user2, $room_id );
      })->then( sub {
         matrix_get_user_dir_synced( $user2, $displayname );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         any { $_->{user_id} eq $user1->user_id } @{ $body->{results} }
            or die "user not in list";

         matrix_leave_room_synced( $user2, $room_id );
      })->then( sub {
         matrix_get_user_dir_synced( $user2, $displayname );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         any { $_->{user_id} eq $user1->user_id } @{ $body->{results} }
            and die "user in list";

         Future->done( 1 );
      });
   };

test "User in dir while user still shares private rooms",
   requires => [ local_user_fixtures( 2 ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my ( $room_id1, $room_id2 );

      my $displayname = generate_random_displayname();

      matrix_set_displayname( $user1, $displayname )
      ->then( sub {
         matrix_create_room( $user1,
            preset => "private_chat", invite => [ $user2->user_id ],
         );
      })->then( sub {
         ( $room_id1 ) = @_;

         matrix_join_room_synced( $user2, $room_id1 );
      })->then( sub {
         matrix_create_room( $user1,
            preset => "private_chat", invite => [ $user2->user_id ],
         );
      })->then( sub {
         ( $room_id2 ) = @_;

         matrix_join_room_synced( $user2, $room_id2 );
      })->then( sub {
         matrix_get_user_dir_synced( $user2, $displayname );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         any { $_->{user_id} eq $user1->user_id } @{ $body->{results} }
            or die "user not in list";

         matrix_leave_room_synced( $user2, $room_id1 );
      })->then( sub {
         matrix_get_user_dir_synced( $user2, $displayname );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         any { $_->{user_id} eq $user1->user_id } @{ $body->{results} }
            or die "user not in list";

         Future->done( 1 );
      });
   };
