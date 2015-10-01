multi_test "Test that we can be reinvited to a room we created",
   requires => [qw(
      local_users remote_users
      can_change_power_levels
   )],

   check => sub {
      my ( $local_users, $remote_users ) = @_;
      my ( $user_1 ) = @$local_users;
      my ( $user_2 ) = @$remote_users;

      my $room_id;

      matrix_create_room( $user_1 )
         ->SyTest::pass_on_done( "User A created a room" )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user_1, $room_id,
            type    => "m.room.join_rules",
            content => { join_rule => "invite" },
         )->SyTest::pass_on_done( "User A set the join rules to 'invite'" )
      })->then( sub {

         matrix_invite_user_to_room( $user_1, $user_2, $room_id )
            ->SyTest::pass_on_done( "User A invited user B" )
      })->then( sub {

         await_event_for( $user_2, sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.room.member";
            return 0 unless $event->{content}->{membership} eq "invite";
            return 0 unless $event->{room_id} eq $room_id;
            return 1;
         })->SyTest::pass_on_done( "User B received the invite from A" )
      })->then( sub {

         matrix_join_room( $user_2, $room_id )
            ->SyTest::pass_on_done( "User B joined the room" )
      })->then( sub {

         matrix_change_room_powerlevels( $user_1, $room_id, sub {
            my ( $levels ) = @_;

            $levels->{users}{ $user_2->user_id } = 100;
         })->SyTest::pass_on_done( "User A set user B's power level to 100" )
      })->then( sub {

         matrix_leave_room( $user_1, $room_id )
            ->SyTest::pass_on_done( "User A left the room" )
      })->then( sub {

         await_event_for( $user_2, sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.room.member";
            return 0 unless $event->{content}->{membership} eq "leave";
            return 0 unless $event->{room_id} eq $room_id;
            return 1;
         })->SyTest::pass_on_done( "User B received the leave event" )
      })->then( sub {

         matrix_invite_user_to_room( $user_2, $user_1, $room_id )
            ->SyTest::pass_on_done( "User B invited user A back to the room" )
      })->then( sub {

         await_event_for( $user_1, sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.room.member";
            return 0 unless $event->{content}->{membership} eq "invite";
            return 0 unless $event->{room_id} eq $room_id;
            return 1;
         })->SyTest::pass_on_done( "User A received the invite from user B" )
      })->then( sub {

         matrix_join_room( $user_1, $room_id )
            ->SyTest::pass_on_done( "User A joined the room" )
      })->then_done(1);
   };
