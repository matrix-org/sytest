test "Add local group users",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

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

test "Remove self from local group",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

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

test "Remove other from local group",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

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

         matrix_remove_group_users( $creator, $group_id, $user );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_list( my $group_ids = $body->{groups} );
         assert_deeply_eq( $group_ids, [] );

         Future->done( 1 );
      });
   };


push our @EXPORT, qw( matrix_invite_group_users matrix_accept_group_invite matrix_get_joined_groups matrix_remove_group_self );


=head2 matrix_invite_group_users

Invite user to group

=cut

sub matrix_invite_group_users
{
   my ( $inviter, $group_id, $invitee ) = @_;

   my $invitee_id = $invitee->user_id;

   do_request_json_for( $inviter,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/admin/users/invite/$invitee_id",
      content => {},
   );
}


=head2 matrix_remove_group_users

Remove another user from group using admin api

=cut

sub matrix_remove_group_users
{
   my ( $inviter, $group_id, $invitee ) = @_;

   my $invitee_id = $invitee->user_id;

   do_request_json_for( $inviter,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/admin/users/remove/$invitee_id",
      content => {},
   );
}


=head2 matrix_accept_group_invite

Accept a received invite

=cut

sub matrix_accept_group_invite
{
   my ( $group_id, $user ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/self/accept_invite",
      content => {},
   );
}


=head2 matrix_remove_group_self

Leave a group that user is in

=cut

sub matrix_remove_group_self
{
   my ( $user, $group_id ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/self/leave",
      content => {},
   );
}


=head2 matrix_get_joined_groups

Get list of groups the user is in. Returns the body of the response,
which is in the form:

    { groups => [ '+foo:bar.com' ] }

=cut

sub matrix_get_joined_groups
{
   my ( $user ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/unstable/joined_groups",
   );
}
