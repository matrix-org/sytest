test "Ignore user in existing room",
   requires => do {
      my $local_user1_fixture = local_user_fixture();
      my $local_user2_fixture = local_user_fixture();
      my $local_user3_fixture = local_user_fixture();

      my $room_fixture = magic_room_fixture(
         requires_users => [ $local_user1_fixture, $local_user2_fixture, $local_user3_fixture ],
      );

      [
         $local_user1_fixture, $local_user2_fixture, $local_user3_fixture,
         $room_fixture, qw( can_send_message can_sync )
      ]
   },

   do => sub {
      my ( $user1, $user2, $user3, $room_id ) = @_;

      my ( $filter_id );

      my $filter = {
         account_data => { types => [ "m.ignored_user_list" ] },
         presence     => { types => [] },
         room         => {
            timeline => { types => [ "m.room.message" ] },
            state    => { types => [ "m.room.member" ] },
         },
      };

      Future->needs_all(
         matrix_send_room_message( $user1, $room_id,
            content => { msgtype => "m.text", body => "Message" }
         ),
         matrix_send_room_message( $user2, $room_id,
            content => { msgtype => "m.text", body => "Message" }
         ),
         matrix_send_room_message( $user3, $room_id,
            content => { msgtype => "m.text", body => "Message" }
         )
      )->then( sub {
         matrix_create_filter( $user1, $filter );
      })->then( sub {
         ( $filter_id ) = @_;

         matrix_sync( $user1, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "First Body", $body;

         my $timeline_events = $body->{rooms}{join}{$room_id}{timeline}{events};
         my $state_events = $body->{rooms}{join}{$room_id}{state}{events};

         assert_eq( scalar @$timeline_events, 3 );
         assert_eq( scalar @$state_events, 3 );

         matrix_add_account_data( $user1, "m.ignored_user_list",
            { "ignored_users" => { $user2->user_id => {} } }
         )
      })->then( sub {
         matrix_sync( $user1, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Second Body", $body;

         my $timeline_events = $body->{rooms}{join}{$room_id}{timeline}{events};
         my $state_events = $body->{rooms}{join}{$room_id}{state}{events};

         assert_eq( scalar @$timeline_events, 2, "Expected only 2 messages" );
         assert_eq( scalar @$state_events, 3, "Expected 3 member state events" );

         matrix_send_room_message( $user2, $room_id,
            content => { msgtype => "m.text", body => "Message2" }
         )
      })->then ( sub {
         matrix_sync_again( $user1, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Third Body", $body;

         my $joined_rooms = $body->{rooms}{join};

         assert_eq( scalar keys %$joined_rooms, 0, "Expected no messages" );

         matrix_send_room_message( $user3, $room_id,
            content => { msgtype => "m.text", body => "Message3" }
         )
      })->then ( sub {
         matrix_sync_again( $user1, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Fourth Body", $body;

         my $timeline_events = $body->{rooms}{join}{$room_id}{timeline}{events};

         assert_eq( scalar @$timeline_events, 1, "Expected only 1 message" );

         Future->done( 1 );
      });
   };


test "Ignore invite in full sync",
   requires => do {
      my $local_user1_fixture = local_user_fixture();
      my $local_user2_fixture = local_user_fixture();

      my $room_fixture = magic_room_fixture(
         requires_users => [ $local_user2_fixture ],
      );

      [
         $local_user1_fixture, $local_user2_fixture,
         $room_fixture, qw( can_send_message can_sync )
      ]
   },

   do => sub {
      my ( $user1, $user2, $room_id ) = @_;

      my ( $filter_id );

      my $filter = {
         account_data => { types => [ "m.ignored_user_list" ] },
         presence     => { types => [] },
         room         => {
            timeline => { types => [ "m.room.message" ] },
            state    => { types => [ "m.room.member" ] },
         },
      };

      matrix_create_filter( $user1, $filter )
      ->then( sub {
         ( $filter_id ) = @_;

         matrix_add_account_data( $user1, "m.ignored_user_list",
            { "ignored_users" => { $user2->user_id => {} } }
         )
      })->then( sub {
         matrix_invite_user_to_room( $user2, $user1, $room_id )
      })->then( sub {
         matrix_sync( $user1, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $invite_rooms = $body->{rooms}{invite};

         assert_eq( scalar keys %$invite_rooms, 0, "Expected no invites" );

         Future->done( 1 );
      });
   };


test "Ignore invite in incremental sync",
   requires => do {
      my $local_user1_fixture = local_user_fixture();
      my $local_user2_fixture = local_user_fixture();

      my $room_fixture = magic_room_fixture(
         requires_users => [ $local_user2_fixture ],
      );

      [
         $local_user1_fixture, $local_user2_fixture,
         $room_fixture, qw( can_send_message can_sync )
      ]
   },

   do => sub {
      my ( $user1, $user2, $room_id ) = @_;

      my ( $filter_id );

      my $filter = {
         account_data => { types => [ "m.ignored_user_list" ] },
         presence     => { types => [] },
         room         => {
            timeline => { types => [ "m.room.message" ] },
            state    => { types => [ "m.room.member" ] },
         },
      };

      matrix_create_filter( $user1, $filter )
      ->then( sub {
         ( $filter_id ) = @_;

         matrix_add_account_data( $user1, "m.ignored_user_list",
            { "ignored_users" => { $user2->user_id => {} } }
         )
      })->then( sub {
         matrix_sync( $user1, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $invite_rooms = $body->{rooms}{invite};

         assert_eq( scalar keys %$invite_rooms, 0, "Expected zero invites" );

         matrix_invite_user_to_room( $user2, $user1, $room_id )
      })->then( sub {
         matrix_sync_again( $user1, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $invite_rooms = $body->{rooms}{invite};

         assert_eq( scalar keys %$invite_rooms, 0, "Expected zero invites" );

         Future->done( 1 );
      });
   };
