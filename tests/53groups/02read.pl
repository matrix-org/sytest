my $local_viewer_fixture = local_user_fixture( with_events => 0 );
my $remote_viewer_fixture = remote_user_fixture( with_events => 0 );

foreach my $viewer_fixture ( $local_viewer_fixture, $remote_viewer_fixture) {
   my $test_name = $viewer_fixture == $local_viewer_fixture ? "local" : "remote";

   test "Get $test_name group profile",
      requires => [ local_admin_fixture( with_events => 0 ), $viewer_fixture ],

      do => sub {
         my ( $user, $viewer ) = @_;

         matrix_create_group( $user,
            name              => "Random Group",
            avatar_url        => "mxc://example.org/foooooo",
            short_description => "A random topic for a random group",
            long_description  => "A longer desc\n\n for a random group",
         )->then( sub {
            my ( $group_id ) = @_;

            matrix_get_group_profile( $viewer, $group_id );
         })->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( name avatar_url short_description long_description ) );

            assert_eq( $body->{name}, "Random Group" );
            assert_eq( $body->{avatar_url}, "mxc://example.org/foooooo" );
            assert_eq( $body->{short_description}, "A random topic for a random group" );
            assert_eq( $body->{long_description}, "A longer desc\n\n for a random group" );

            Future->done( 1 );
         });
      };

   test "Get $test_name group users",
      requires => [ local_admin_fixture( with_events => 0 ), $viewer_fixture ],

      do => sub {
         my ( $user, $viewer ) = @_;

         matrix_create_group( $user )
         ->then( sub {
            my ( $group_id ) = @_;

            matrix_get_group_users( $viewer, $group_id );
         })->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( chunk ) );

            any { $_->{user_id} eq $user->user_id } @{ $body->{chunk} }
               or die "Creator not in group users list";

            Future->done( 1 );
         });
      };

   test "Add $test_name group rooms",
      requires => [ local_admin_fixture( with_events => 0 ), $viewer_fixture ],

      do => sub {
         my ( $user, $viewer ) = @_;

         my ( $group_id, $room_id );

         matrix_create_group( $user )
         ->then( sub {
            ( $group_id ) = @_;

            matrix_create_room( $user );
         })->then( sub {
            ( $room_id ) = @_;

            matrix_add_group_rooms( $user, $group_id, $room_id );
         })->then( sub {
            matrix_get_group_rooms( $viewer, $group_id );
         })->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( chunk ) );

            any { $_->{room_id} eq $room_id } @{ $body->{chunk} }
               or die "Room not in group rooms list";

            Future->done( 1 );
         });
      };

   test "Add $test_name group users",
      requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ), $viewer_fixture ],

      do => sub {
         my ( $creator, $user, $viewer ) = @_;

         my $group_id;

         matrix_create_group( $creator )
         ->then( sub {
            ( $group_id ) = @_;

            matrix_add_group_users( $creator, $group_id, $user );
         })->then( sub {
            matrix_get_group_users( $viewer, $group_id );
         })->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( chunk ) );

            any { $_->{user_id} eq $user->user_id } @{ $body->{chunk} }
               or die "New user not in group users list";

            Future->done( 1 );
         });
      };

   test "Get $test_name group summary",
      requires => [ local_admin_fixture( with_events => 0 ), $viewer_fixture ],

      do => sub {
         my ( $user, $viewer ) = @_;

         my ( $group_id, $room_id );

         matrix_create_group( $user,
            name => "Testing summaries",
         )
         ->then( sub {
            ( $group_id ) = @_;

            matrix_create_room( $user );
         })->then( sub {
            ( $room_id ) = @_;

            matrix_add_group_rooms( $user, $group_id, $room_id );
         })->then( sub {
            matrix_get_group_summary( $viewer, $group_id );
         })->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( profile users rooms ) );

            assert_eq( $body->{profile}{name}, "Testing summaries" );

            any { $_->{room_id} eq $room_id } @{ $body->{rooms}{chunk} }
               or die "Room not in group rooms list";

            any { $_->{user_id} eq $user->user_id } @{ $body->{users}{chunk} }
               or die "New user not in group users list";

            Future->done( 1 );
         });
      };
}

push our @EXPORT, qw( matrix_get_group_profile matrix_get_group_users matrix_get_group_rooms matrix_get_group_summary );

sub matrix_get_group_profile
{
   my ( $user, $group_id ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/unstable/groups/$group_id/profile",
   );
}

sub matrix_get_group_users
{
   my ( $user, $group_id ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/unstable/groups/$group_id/users",
   );
}

sub matrix_get_group_rooms
{
   my ( $user, $group_id ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/unstable/groups/$group_id/rooms",
   );
}

sub matrix_get_group_summary
{
   my ( $user, $group_id ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/unstable/groups/$group_id/summary",
   );
}
