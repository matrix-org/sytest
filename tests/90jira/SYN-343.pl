multi_test "Non-present room members cannot ban others",
   requires => [qw(
      change_room_powerlevels local_users
      can_ban_room
   )],

   await => sub {
      my ( $change_room_powerlevels, $local_users ) = @_;
      my $creator = $local_users->[0];
      my $testuser = $local_users->[1];

      my $room_id;

      matrix_create_room( $creator )
         ->SyTest::pass_on_done( "Created room" )
      ->then( sub {
         ( $room_id ) = @_;

         $change_room_powerlevels->( $creator, $room_id, sub {
            my ( $levels ) = @_;
            $levels->{users}{ $testuser->user_id } = 100;
         })->SyTest::pass_on_done( "Set powerlevel" )
      })->then( sub {

         do_request_json_for( $testuser,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/ban",

            content => { user_id => '@random_dude:test', reason => "testing" },
         )->main::expect_http_403
         ->SyTest::pass_on_done( "Attempt to ban is rejected" )
      })->then_done(1);
   };
