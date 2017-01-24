test "Room members can override their displayname on a room-specific basis",
   bug => "#1382",

   requires => [ local_user_and_room_fixtures() ],

   do => sub {
      my ( $user, $room_id ) = @_;

      matrix_put_room_state( $user, $room_id,
         type      => "m.room.member",
         state_key => $user->user_id,
         content   => {
            membership => "join",
            displayname => "Overridden",
         },
      )->then( sub {
         matrix_get_room_state( $user, $room_id,
            type      => "m.room.member",
            state_key => $user->user_id,
         );
      })->then( sub {
         my ( $state ) = @_;

         log_if_fail "State", $state;

         assert_eq( $state->{displayname}, "Overridden",
            'displayname in my m.room.member event' );

         Future->done(1);
      });
   };

test "Room members can join a room with an overridden displayname",
   bug => "#1382",

   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $joiner ) = @_;

      # PUT'ing my membership state should join me
      matrix_put_room_state( $joiner, $room_id,
         type      => "m.room.member",
         state_key => $joiner->user_id,
         content   => {
            membership => "join",
            displayname => "Overridden",
         },
      )->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.member",
            state_key => $joiner->user_id,
         );
      })->then( sub {
         my ( $state ) = @_;

         log_if_fail "State", $state;

         assert_eq( $state->{displayname}, "Overridden",
            'displayname in my m.room.member event at join time' );

         Future->done(1);
      });
   };
