test "Create group",
   deprecated_endpoints => 1,
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my $localpart = make_group_localpart();
      my $server_name = $user->http->server_name;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/r0/create_group",
         content => {
            localpart => $localpart,
            profile   => {
               name => "Test Group",
            },
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( group_id ) );
         assert_eq( $body->{group_id}, "+$localpart:$server_name");

         Future->done( 1 );
      });
   };

test "Add group rooms",
   deprecated_endpoints => 1,
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_group_rooms( $user, $group_id, $room_id );
      });
   };


test "Remove group rooms",
   deprecated_endpoints => 1,
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_group_rooms( $user, $group_id, $room_id );
      })->then( sub {
         matrix_remove_group_rooms( $user, $group_id, $room_id );
      });
   };


push our @EXPORT, qw( matrix_create_group matrix_add_group_rooms matrix_remove_group_rooms );


=head2 matrix_create_group

   matrix_create_group( $user, %profile )

Creates a group as the given user, and optionally the given profile.
Returns a Future for the created group_id.

For example:

    matrix_create_group( $creator, name => "My new group" )

=cut

sub matrix_create_group
{
   my ( $user, %opts ) = @_;

   my $localpart = make_group_localpart();

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/r0/create_group",
      content => {
         localpart => $localpart,
         profile   => { %opts },
      },
   )->then( sub {
      my ( $body ) = @_;

      Future->done( $body->{group_id} );
   });
}


=head2 matrix_add_group_rooms

   matrix_add_group_rooms( $user, $group_id, $room_id )

Add room to group as given user.

=cut

sub matrix_add_group_rooms
{
   my ( $user, $group_id, $room_id ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/groups/$group_id/admin/rooms/$room_id",
      content => {},
   );
}



=head2 matrix_remove_group_rooms

   matrix_remove_group_rooms( $user, $group_id, $room_id )

Remove room from group as given user.

=cut

sub matrix_remove_group_rooms
{
   my ( $user, $group_id, $room_id ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/r0/groups/$group_id/admin/rooms/$room_id",
   );
}


my $next_group_localpart = 0;

sub make_group_localpart
{
   sprintf "__anon__-%s-%d", $TEST_RUN_ID, $next_group_localpart++;
}
