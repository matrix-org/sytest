test "Add local group users",
   deprecated_endpoints => 1,
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

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

         assert_json_keys( $body, qw( groups ) );
         assert_json_list( my $group_ids = $body->{groups} );

         assert_deeply_eq( $group_ids, [ $group_id ] );

         Future->done( 1 );
      });
   };

test "Remove self from local group",
   deprecated_endpoints => 1,
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

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

test "Remove other from local group",
   deprecated_endpoints => 1,
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

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

         matrix_remove_group_user( $creator, $group_id, $user );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_deeply_eq( $body->{groups}, [] );

         Future->done( 1 );
      });
   };


push our @EXPORT, qw( matrix_invite_group_user matrix_accept_group_invite matrix_get_joined_groups matrix_leave_group matrix_join_group matrix_get_invited_group_users );


=head2 matrix_invite_group_user

   matrix_invite_group_user( $inviter, $group_id, $invitee )

Invite user to group

=cut

sub matrix_invite_group_user
{
   my ( $inviter, $group_id, $invitee ) = @_;

   my $invitee_id = $invitee->user_id;

   do_request_json_for( $inviter,
      method  => "PUT",
      uri     => "/r0/groups/$group_id/admin/users/invite/$invitee_id",
      content => {},
   );
}


=head2 matrix_remove_group_user

   matrix_remove_group_user( $inviter, $group_id, $invitee )

Remove another user from group using admin api

=cut

sub matrix_remove_group_user
{
   my ( $inviter, $group_id, $invitee ) = @_;

   my $invitee_id = $invitee->user_id;

   do_request_json_for( $inviter,
      method  => "PUT",
      uri     => "/r0/groups/$group_id/admin/users/remove/$invitee_id",
      content => {},
   );
}


=head2 matrix_accept_group_invite

   matrix_accept_group_invite( $group_id, $user )

Accept a received invite

=cut

sub matrix_accept_group_invite
{
   my ( $group_id, $user ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/groups/$group_id/self/accept_invite",
      content => {},
   );
}


=head2 matrix_join_group

   matrix_join_group( $group_id, $user )

Join a group

=cut

sub matrix_join_group
{
   my ( $group_id, $user ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/groups/$group_id/self/join",
      content => {},
   );
}


=head2 matrix_leave_group

   matrix_leave_group( $user, $group_id )

Leave a group that user is in

=cut

sub matrix_leave_group
{
   my ( $user, $group_id ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/groups/$group_id/self/leave",
      content => {},
   );
}


=head2 matrix_get_joined_groups

   matrix_get_joined_groups( $user )

Get list of groups the user is in. Returns the body of the response,
which is in the form:

    { groups => [ '+foo:bar.com' ] }

=cut

sub matrix_get_joined_groups
{
   my ( $user ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/r0/joined_groups",
   );
}

=head2 matrix_get_invited_group_users

    matrix_get_invited_group_users( $group_id, $user )

Get a list of invited group members. Returns the body of the response, which
is in the form:

    {
        chunk => [
            {
                user_id     => '@someone:example.org',
                avatar_url  => 'mxc://example.org/something',
                displayname => 'Example User'
            }
        ],
        total_user_count_estimate => 1
    }

=cut

sub matrix_get_invited_group_users
{
    my ( $group_id, $user ) = @_;

    do_request_json_for( $user,
        method => "GET",
        uri    => "/r0/groups/$group_id/invited_users"
    )
}
