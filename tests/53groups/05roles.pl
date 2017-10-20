test "Add group role",
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_role_to_group( $user, $group_id, "some_role",
            profile => { name => "Role Name" }
         );
      })->then( sub {
         matrix_get_group_role( $user, $group_id, "some_role" );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw ( is_public profile ) );
         assert_deeply_eq( $body->{profile}, { name => "Role Name" } );

         Future->done( 1 );
      });
   };

test "Remove group role",
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_role_to_group( $user, $group_id, "some_role" );
      })->then( sub {
         matrix_remove_role_from_group( $user, $group_id, "some_role" );
      })->then( sub {
         matrix_get_group_role( $user, $group_id, "some_role" );
      })->main::expect_http_404;
   };


test "Get group roles",
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_role_to_group( $user, $group_id, "some_role1",
            profile => { name => "Role Name 1" }
         );
      })->then( sub {
         matrix_add_role_to_group( $user, $group_id, "some_role2",
            profile => { name => "Role Name 2" }
         );
      })->then( sub {
         matrix_get_group_roles( $user, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw ( roles ) );
         assert_json_keys( $body->{roles}, qw( some_role1 some_role2 ) );

         assert_deeply_eq( $body->{roles}{some_role1}{profile}, { name => "Role Name 1" } );
         assert_deeply_eq( $body->{roles}{some_role2}{profile}, { name => "Role Name 2" } );

         Future->done( 1 );
      });
   };


push our @EXPORT, qw( matrix_add_role_to_group );


=head2 matrix_add_role_to_group

Create a role for a group. Extra options are passed directly into the
content of the request.

   matrix_add_role_to_group( $user, $group_id, "some_role1",
      profile => { name => "Role Name 1" }
   );

=cut

sub matrix_add_role_to_group
{
   my ( $user, $group_id, $role_id, %opts ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/roles/$role_id",
      content => \%opts,
   );
}

sub matrix_get_group_role
{
   my ( $user, $group_id, $role_id ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/unstable/groups/$group_id/roles/$role_id",
   );
}

sub matrix_remove_role_from_group
{
   my ( $user, $group_id, $role_id ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/unstable/groups/$group_id/roles/$role_id",
   );
}

sub matrix_get_group_roles
{
   my ( $user, $group_id ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/unstable/groups/$group_id/roles/",
   );
}
