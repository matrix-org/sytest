test "Add remote group users",
   requires => [ local_admin_fixture( with_events => 0 ), remote_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_invite_group_user( $creator, $group_id, $user );
      })->then( sub {
         matrix_accept_group_invite( $group_id, $user );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_deeply_eq( $body->{groups}, [ $group_id ] );

         Future->done( 1 );
      });
   };

test "Remove self from remote group",
   requires => [ local_admin_fixture( with_events => 0 ), remote_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_invite_group_user( $creator, $group_id, $user );
      })->then( sub {
         matrix_accept_group_invite( $group_id, $user );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_deeply_eq( $body->{groups}, [ $group_id ] );

         matrix_leave_group( $user, $group_id );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_deeply_eq( $body->{groups}, [] );

         Future->done( 1 );
      });
   };

test "Listing invited users of a remote group when not a member returns a 403",
    requires => [ local_admin_fixture( with_events => 0 ), remote_user_fixture( with_events => 0 ) ],

    do => sub {
        my ( $creator, $user ) = @_;

        my $group_id;

        matrix_create_group( $creator )
        ->then( sub {
            ( $group_id ) = @_;

            matrix_get_invited_group_users( $group_id, $user )
            -> main::expect_http_403;
        });
    };

# TODO: Test kicks
