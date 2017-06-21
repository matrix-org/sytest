test "Add remote group users",
   requires => [ local_admin_fixture( with_events => 0 ), remote_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_invite_group_users( $creator, $group_id, $user );
      })->then( sub {
         matrix_accept_group_invite( $group_id, $user );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( groups ) );
         assert_json_list( my $group_ids = $body->{groups} );

         assert_deeply_eq( $group_ids, [ $group_id ] );

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

         matrix_invite_group_users( $creator, $group_id, $user );
      })->then( sub {
         matrix_accept_group_invite( $group_id, $user );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_list( my $group_ids = $body->{groups} );
         assert_deeply_eq( $group_ids, [ $group_id ] );

         matrix_remove_group_self( $user, $group_id );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_list( my $group_ids = $body->{groups} );
         assert_deeply_eq( $group_ids, [] );

         Future->done( 1 );
      });
   };


# TODO: Test kicks
