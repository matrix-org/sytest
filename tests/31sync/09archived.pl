test "Left rooms appear in the leave section of sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      matrix_create_filter( $user,
         { room => { include_leave => JSON::true } }
      )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_leave_room_and_wait_for_sync( $user, $room_id );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         assert_json_keys( $room, qw( timeline state ));

         Future->done(1);
      });
   };


test "Newly left rooms appear in the leave section of incremental sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

     matrix_create_filter( $user,
         { room => { include_leave => JSON::true } }
     )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_and_wait_for_sync( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_leave_room_and_wait_for_sync( $user, $room_id );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         assert_json_keys( $room, qw( timeline state ));

         @{ $room->{state}{events} } == 0
            or die "Expected no state events";

         Future->done(1);
      });
   };

test "We should see our own leave event, even if history_visibility is " .
    "restricted (SYN-662)",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

     matrix_create_filter( $user,
         { room => { include_leave => JSON::true } }
     )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state_and_wait_for_sync( $user, $room_id,
            type    => "m.room.history_visibility",
            content => { history_visibility => "joined" },
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_leave_room_and_wait_for_sync( $user, $room_id );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "sync result", $body;

         my $room = $body->{rooms}{leave}{$room_id};
         assert_json_keys( $room, qw( timeline state ));

         assert_eq( scalar @{ $room->{state}{events} }, 0,
                    "state events" );

         # we should see our own leave event
         assert_eq( scalar @{ $room->{timeline}{events} }, 1,
                    "timeline events");
         my $ev = $room->{timeline}{events}[0];
         assert_eq( $ev->{type}, "m.room.member", "event type" );
         assert_eq( $ev->{content}{membership}, "leave", "membership" );

         Future->done(1);
      });
   };

test "Newly left rooms appear in the leave section of gapped sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id_1, $room_id_2 );

      my $filter = {
         room => { timeline => { limit => 1 }, include_leave => JSON::true }
      };

      matrix_create_filter( $user, {} )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user )->on_done( sub { ( $room_id_1 ) = @_; } );
      })->then( sub {
         matrix_create_room_and_wait_for_sync($user )->on_done( sub {
            ( $room_id_2 ) = @_; }
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_leave_room( $user, $room_id_1 );
      })->then( sub {
         # Pad out the timeline with filler messages to create a "gap" between
         # this sync and the next. It's useful to test this since
         # implementations of matrix are likely to take different code paths
         # if there were many messages between a since that if there were only
         # a few.
         Future->needs_all( map {
            matrix_send_room_message( $user, $room_id_2,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 19 );
      })->then( sub {
         matrix_send_room_message_and_wait_for_sync( $user, $room_id_2,
            content => { "filler" => 20 },
            type    => "a.made.up.filler.type",
         );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id_1};
         assert_json_keys( $room, qw( timeline state ));

         Future->done(1);
      });
   };


test "Previously left rooms don't appear in the leave section of sync",
   requires => [ local_user_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user, $user2 ) = @_;

      my ( $filter_id, $room_id_1, $room_id_2 );

      my $filter = {
         room => { timeline => { limit => 1 }, include_leave => JSON::true }
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         Future->needs_all(
            matrix_create_room( $user )->on_done( sub { ( $room_id_1 ) = @_; } ),
            matrix_create_room( $user )->on_done( sub { ( $room_id_2 ) = @_; } ),
         );
      })->then( sub {
         matrix_join_room( $user2, $room_id_1 );
      })->then( sub {
         matrix_join_room_and_wait_for_sync( $user2, $room_id_2 );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_leave_room_and_wait_for_sync( $user, $room_id_1 );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         matrix_put_room_state( $user2, $room_id_1,
            content  => { "filler" => $_, membership => "join" },
            type      => "m.room.member",
            state_key => $user2->user_id,
         )
      })->then( sub {
         # Pad out the timeline with filler messages to create a "gap" between
         # this sync and the next.
         Future->needs_all( map {
            matrix_send_room_message( $user2, $room_id_2,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         }  0 .. 4 );

      })->then( sub {
         matrix_send_room_message_and_wait_for_sync( $user2, $room_id_2,
            content => { "filler" => 5 },
            type    => "a.made.up.filler.type",
         );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $leave = $body->{rooms}{leave};

         assert_json_object( $leave );
         keys %$leave == 0 or die "Expected no rooms in 'leave' state";

         Future->done(1);
      });
   };



test "Left rooms appear in the leave section of full state sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      matrix_create_filter( $user,
         { room => { include_leave => JSON::true } }
      )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_and_wait_for_sync( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_leave_room_and_wait_for_sync( $user, $room_id );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id, full_state => 'true' );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         assert_json_keys( $room, qw( timeline state ));

         Future->done(1);
      });
   };


test "Archived rooms only contain history from before the user left",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id, $next_b );

      my $filter = {
         room => {
            timeline => { types => [ "m.room.message", "a.madeup.test.state" ] },
            state => { types => [ "a.madeup.test.state" ] },
            include_leave => JSON::true,
         },
      };

      Future->needs_all(
         matrix_create_filter( $user_a, $filter ),
         matrix_create_filter( $user_b, $filter ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room_and_wait_for_sync( $user_b, $room_id );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         $next_b = $body->{next_batch};

         matrix_send_room_text_message( $user_a, $room_id, body => "before" );
      })->then( sub {
         matrix_put_room_state( $user_a, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => "before" },
            state_key => "",
         );
      })->then( sub {
         matrix_leave_room( $user_b, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $user_a, $room_id, body => "after" );
      })->then( sub {
         matrix_put_room_state_and_wait_for_sync( $user_a, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => "after" },
            state_key => "",
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         assert_json_keys( $room, qw( timeline state ));
         @{ $room->{state}{events} } == 0
            or die "Expected no state events";
         @{ $room->{timeline}{events} } == 2
            or die "Expected two timeline events";

         my $timeline_event = $room->{timeline}{events}[0];
         $timeline_event->{content}{body} eq "before"
            or die "Expected only events from before leaving";

         matrix_sync( $user_b, filter => $filter_id_b, since => $next_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         assert_json_keys( $room, qw( timeline state ));
         @{ $room->{state}{events} } == 0
            or die "Expected no state events";
         @{ $room->{timeline}{events} } == 2
            or die "Expected two timeline events";

         my $timeline_event = $room->{timeline}{events}[0];
         $timeline_event->{content}{body} eq "before"
            or die "Expected only events from before leaving";

         Future->done(1);
      });
   };
