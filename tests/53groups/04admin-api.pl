test "Remove local users from group",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_group_users( $creator, $group_id, $user );
      })->then( sub {
         matrix_get_group_users( $creator, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         any { $_->{user_id} eq $user->user_id } @{ $body->{chunk} }
            or die "New user not in group users list";

         matrix_remove_group_users( $creator, $group_id, $user );
      })->then( sub {
         matrix_get_group_users( $creator, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         any { $_->{user_id} eq $user->user_id } @{ $body->{chunk} }
            and die "Removed user in group users list";

         Future->done( 1 );
      });
   };
