multi_test "Non-present room members cannot ban others",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_ban_room can_change_power_levels )],

   do => sub {
      my ( $creator, $testuser ) = @_;

      my $room_id;

      matrix_create_room( $creator )
         ->SyTest::pass_on_done( "Created room" )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_change_room_power_levels( $creator, $room_id, sub {
            my ( $levels ) = @_;
            $levels->{users}{ $testuser->user_id } = 100;
         })->SyTest::pass_on_done( "Set powerlevel" )
      })->then( sub {

         do_request_json_for( $testuser,
            method => "POST",
            uri    => "/r0/rooms/$room_id/ban",

            content => { user_id => '@random_dude:test', reason => "testing" },
         )->main::expect_http_403
         ->SyTest::pass_on_done( "Attempt to ban is rejected" )
      })->then_done(1);
   };
