test "Create group",
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my $localpart = make_group_localpart();
      my $server_name = $user->http->server_name;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/unstable/create_group",
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


push our @EXPORT, qw( matrix_create_group matrix_add_group_rooms );

sub matrix_create_group
{
   my ( $user, %opts ) = @_;

   my $localpart = make_group_localpart();

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/unstable/create_group",
      content => {
         localpart => $localpart,
         profile   => { %opts },
      },
   )->then( sub {
      my ( $body ) = @_;

      Future->done( $body->{group_id} );
   });
}


sub matrix_add_group_rooms
{
   my ( $user, $group_id, $room_id ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/admin/rooms/$room_id",
      content => {},
   );
}



my $next_group_localpart = 0;

sub make_group_localpart
{
   sprintf "__ANON__-%d", $next_group_localpart++;
}
