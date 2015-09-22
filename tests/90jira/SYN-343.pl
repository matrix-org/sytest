multi_test "Non-present room members cannot ban others",
   requires => [qw(
      make_test_room do_request_json_for change_room_powerlevels local_users
         expect_http_403
      can_ban_room
   )],

   await => sub {
      my (
         $make_test_room, $do_request_json_for, $change_room_powerlevels, $local_users,
         $expect_http_403
      ) = @_;
      my $creator = $local_users->[0];
      my $testuser = $local_users->[1];

      my $room_id;

      $make_test_room->( $creator )
         ->on_done( sub { pass "Created room" } )
      ->then( sub {
         ( $room_id ) = @_;

         $change_room_powerlevels->( $creator, $room_id, sub {
            my ( $levels ) = @_;
            $levels->{users}{ $testuser->user_id } = 100;
         })->on_done( sub { pass "Set powerlevel" } )
      })->then( sub {

         $do_request_json_for->( $testuser,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/ban",

            content => { user_id => '@random_dude:test', reason => "testing" },
         )->$expect_http_403
         ->on_done( sub { pass "Attempt to ban is rejected" } )
      })->then_done(1);
   };
