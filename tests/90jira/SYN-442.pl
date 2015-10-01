multi_test "Test that we can be reinvited to a room we created",
   requires => [qw(
      change_room_powerlevels local_users remote_users
   )],

   check => sub {
      my ( $change_room_powerlevels, $local_users, $remote_users ) = @_;
      my ( $user_1 ) = @$local_users;
      my ( $user_2 ) = @$remote_users;

      my $room_id;

      matrix_create_room( $user_1 )
         ->SyTest::pass_on_done( "User A created a room" )
      ->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $user_1,
            method  => "PUT",
            uri     => "/api/v1/rooms/$room_id/state/m.room.join_rules",
            content => { join_rule => "invite" },
         )->SyTest::pass_on_done( "User A set the join rules to 'invite'" )
      })->then( sub {

         do_request_json_for( $user_1,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/invite",
            content => { user_id => $user_2->user_id },
         )->SyTest::pass_on_done( "User A invited user B" )
      })->then( sub {

         await_event_for( $user_2, sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.room.member";
            return 0 unless $event->{content}->{membership} eq "invite";
            return 0 unless $event->{room_id} eq $room_id;
            return 1;
         })->SyTest::pass_on_done( "User B received the invite from A" )
      })->then( sub {

         do_request_json_for( $user_2,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/join",
            content => {},
         )->SyTest::pass_on_done( "User B joined the room" )
      })->then( sub {

         $change_room_powerlevels->( $user_1, $room_id, sub {
            my ( $levels ) = @_;

            $levels->{users}{ $user_2->user_id } = 100;
         })->SyTest::pass_on_done( "User A set user B's power level to 100" )
      })->then( sub {

         do_request_json_for( $user_1,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/leave",
            content => {},
         )->SyTest::pass_on_done( "User A left the room" )
      })->then( sub {

         await_event_for( $user_2, sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.room.member";
            return 0 unless $event->{content}->{membership} eq "leave";
            return 0 unless $event->{room_id} eq $room_id;
            return 1;
         })->SyTest::pass_on_done( "User B received the leave event" )
      })->then( sub {

         do_request_json_for( $user_2,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/invite",
            content => { user_id => $user_1->user_id },
         )->SyTest::pass_on_done( "User B invited user A back to the room" )
      })->then( sub {

         await_event_for( $user_1, sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.room.member";
            return 0 unless $event->{content}->{membership} eq "invite";
            return 0 unless $event->{room_id} eq $room_id;
            return 1;
         })->SyTest::pass_on_done( "User A received the invite from user B" )
      })->then( sub {

         do_request_json_for( $user_1,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/join",
            content => {},
         )->SyTest::pass_on_done( "User A joined the room" )
      })->then_done(1);
   };
