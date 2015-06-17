multi_test "AS-ghosted users can use rooms via AS",
   requires => [qw( make_test_room make_as_user do_request_json_for await_event_for user as_user
                    can_join_room_by_id can_receive_room_message_locally )],

   do => sub {
      my ( $make_test_room, $make_as_user, $do_request_json_for, $await_event_for, $user, $as_user ) = @_;

      my $room_id;
      my $ghost;

      $make_test_room->( $user )->then( sub {
         ( $room_id ) = @_;

         pass "Created test room";

         $make_as_user->( "02ghost-1" )
      })->then( sub {
         ( $ghost ) = @_;

         pass "Created AS ghost";

         $do_request_json_for->( $as_user,
            method => "POST",
            uri    => "/rooms/$room_id/join",
            params => {
               user_id => $ghost->user_id,
            },

            content => {},
         )
      })->then( sub {
         pass "User joined room via AS";

         $do_request_json_for->( $as_user,
            method => "POST",
            uri    => "/rooms/$room_id/send/m.room.message",
            params => {
               user_id => $ghost->user_id,
            },

            content => { msgtype => "m.text", body => "Message from AS directly" },
         )
      })->then( sub {
         pass "User posted message via AS";

         $await_event_for->( $user, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{room_id} eq $room_id;

            log_if_fail "Event", $event;

            my $content = $event->{content};

            $content->{body} eq "Message from AS directly" or
               die "Expected 'body' as 'Message from AS directly'";
            $event->{user_id} eq $ghost->user_id or
               die "Expected sender user_id as ${\$ghost->user_id}";

            return 1;
         })
      })->then( sub {
         pass "Creator received user's message";

         Future->done(1);
      });
   };

multi_test "AS-ghosted users can use rooms themselves",
   requires => [qw( make_test_room make_as_user do_request_json_for await_event_for user
                    can_join_room_by_id can_receive_room_message_locally )],

   do => sub {
      my ( $make_test_room, $make_as_user, $do_request_json_for, $await_event_for, $user ) = @_;

      my $room_id;
      my $ghost;

      $make_test_room->( $user )->then( sub {
         ( $room_id ) = @_;

         pass "Created test room";

         $make_as_user->( "02ghost-2" )
      })->then( sub {
         ( $ghost ) = @_;

         pass "Created AS ghost";

         $do_request_json_for->( $ghost,
            method => "POST",
            uri    => "/rooms/$room_id/join",

            content => {},
         )
      })->then( sub {
         pass "Ghost joined room themselves";

         $do_request_json_for->( $ghost,
            method => "POST",
            uri    => "/rooms/$room_id/send/m.room.message",

            content => { msgtype => "m.text", body => "Message from AS Ghost" },
         )
      })->then( sub {
         pass "Ghost posted message themselves";

         $await_event_for->( $user, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{room_id} eq $room_id;

            log_if_fail "Event", $event;

            my $content = $event->{content};

            $content->{body} eq "Message from AS Ghost" or
               die "Expected 'body' as 'Message from AS Ghost'";
            $event->{user_id} eq $ghost->user_id or
               die "Expected sender user_id as ${\$ghost->user_id}";

            return 1;
         })
      })->then( sub {
         pass "Creator received ghost's message";

         Future->done(1);
      });
   };
