multi_test "Rooms can be created with an initial invite list (SYN-205)",
   requires => [qw( do_request_json_for await_event_for user more_users
                    can_register can_create_private_room_with_invite )],

   do => sub {
      my ( $do_request_json_for, $await_event_for, $user, $more_users ) = @_;
      my $invitee = $more_users->[0];

      my $room;

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/api/v1/createRoom",

         content => { visibility => "private", invite => [ $invitee->user_id ] },
      )->SyTest::pass_on_done( "Created room" )
      ->then( sub {
         ( $room ) = @_;

         $await_event_for->( $invitee, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member" and
                          $event->{room_id} eq $room->{room_id} and
                          $event->{state_key} eq $invitee->user_id and
                          $event->{content}{membership} eq "invite";

            return 1;
         })->SyTest::pass_on_done( "Invitee received invite event" )
      })->then_done(1);
   };
