multi_test "Rooms can be created with an initial invite list (SYN-205)",
   requires => [ local_user_fixtures( 2 ),
                qw( can_create_private_room_with_invite )],

   do => sub {
      my ( $user, $invitee ) = @_;

      matrix_create_room( $user,
         invite => [ $invitee->user_id ],
      )->SyTest::pass_on_done( "Created room" )
      ->then( sub {
         my ( $room_id ) = @_;

         await_event_for( $invitee, sub {
            my ( $event ) = @_;

            return $event->{type} eq "m.room.member" &&
                   $event->{room_id} eq $room_id &&
                   $event->{state_key} eq $invitee->user_id &&
                   $event->{content}{membership} eq "invite";
         })->SyTest::pass_on_done( "Invitee received invite event" )
      })->then_done(1);
   };
