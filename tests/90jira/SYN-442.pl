multi_test "Test that we can be reinvited to a room we created",
   requires => [qw(
      do_request_json_for await_event_for change_room_powerlevels local_users remote_users
   )],

   check => sub {
      my (
         $do_request_json_for, $await_event_for, $change_room_powerlevels, $local_users, $remote_users
      ) = @_;
      my ( $user_1 ) = @$local_users;
      my ( $user_2 ) = @$remote_users;

      my $room_id;

      $do_request_json_for->( $user_1,
         method  => "POST",
         uri     => "/api/v1/createRoom",
         content => {},
      )->then( sub {
         my ( $body ) = @_;

         pass "User A created a room";

         require_json_keys( $body, qw(room_id));
         $room_id = $body->{room_id};

         $do_request_json_for->( $user_1,
            method  => "PUT",
            uri     => "/api/v1/rooms/$room_id/state/m.room.join_rules",
            content => { join_rule => "invite" },
         );
      })->then( sub {
         pass "User A set the join rules to 'invite'";

         $do_request_json_for->( $user_1,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/invite",
            content => { user_id => $user_2->user_id },
         );
      })->then( sub {
         pass "User A invited user B";

         $await_event_for->( $user_2, sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.room.member";
            return 0 unless $event->{content}->{membership} eq "invite";
            return 0 unless $event->{room_id} eq $room_id;
            return 1;
         });
      })->then( sub {
         pass "User B received the invite from A";

         $do_request_json_for->( $user_2,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/join",
            content => {},
         );
      })->then( sub {
         pass "User B joined the room";

         $change_room_powerlevels->( $user_1, $room_id, sub {
            my ( $levels ) = @_;

            $levels->{users}{ $user_2->user_id } = 100;
         });
      })->then( sub {
         pass "User A set user B's power level to 100";

         $do_request_json_for->( $user_1,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/leave",
            content => {},
         );
      })->then( sub {
         pass "User A left the room";

         $await_event_for->( $user_2, sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.room.member";
            return 0 unless $event->{content}->{membership} eq "leave";
            return 0 unless $event->{room_id} eq $room_id;
            return 1;
         });
      })->then( sub {
         pass "User B received the leave event";

         $do_request_json_for->( $user_2,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/invite",
            content => { user_id => $user_1->user_id },
         );
      })->then( sub {
         pass "User B invited user A back to the room";

         $await_event_for->( $user_1, sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.room.member";
            return 0 unless $event->{content}->{membership} eq "invite";
            return 0 unless $event->{room_id} eq $room_id;
            return 1;
         });
      })->then( sub {
         pass "User A received the invite from B";

         $do_request_json_for->( $user_1,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/join",
            content => {},
         );
      })->then( sub {
         pass "User A joined the room";

         Future->done(1);
      });
   };
