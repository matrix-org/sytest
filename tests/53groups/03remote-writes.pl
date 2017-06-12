test "Add remote users to group",
   requires => [ local_admin_fixture( with_events => 0 ), remote_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $remote ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_group_users( $creator, $group_id, $remote );
      })->then( sub {
         matrix_get_group_users( $creator, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         any { $_->{user_id} eq $remote->user_id } @{ $body->{chunk} }
            or die "New user not in group users list";

         matrix_get_group_users( $remote, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         any { $_->{user_id} eq $remote->user_id } @{ $body->{chunk} }
            or die "New user not in group users list";

         Future->done( 1 );
      });
   };
