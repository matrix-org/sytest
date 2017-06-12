my $local_viewer_fixture = local_user_fixture( with_events => 0 );
my $remote_viewer_fixture = remote_user_fixture( with_events => 0 );

foreach my $user_fixture ( $local_viewer_fixture, $remote_viewer_fixture) {
   my $test_name = $user_fixture == $local_viewer_fixture ? "local" : "remote";

   test "Remove self from $test_name group",
      requires => [ local_admin_fixture( with_events => 0 ), $user_fixture ],

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

            matrix_remove_group_self( $user, $group_id );
         })->then( sub {
            matrix_get_group_users( $creator, $group_id );
         })->then( sub {
            my ( $body ) = @_;

            any { $_->{user_id} eq $user->user_id } @{ $body->{chunk} }
               and die "Removed user in group users list";

            Future->done( 1 );
         });
      };
}



sub matrix_remove_group_self
{
   my ( $user, $group_id ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/self/leave",
      content => {},
   );
}
