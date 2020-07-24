multi_test "Rooms can be created with an initial invite list (SYN-205)",
   requires => [ local_user_fixtures( 2, with_events => 1 ),
                qw( can_create_private_room_with_invite )],

   do => sub {
      my ( $user, $invitee ) = @_;

      matrix_create_room( $user,
         invite => [ $invitee->user_id ],
      )->SyTest::pass_on_done( "Created room" )
      ->then( sub {
         my ( $room_id ) = @_;

         await_sync($invitee, check => sub {
            my ( $sync_body ) = @_;
            log_if_fail $sync_body;
            my $room =  $sync_body->{rooms}{invite}{$room_id};
            assert_json_keys( $room, qw( invite_state ) );
            assert_json_keys( $room->{invite_state}, qw( events ) );
            my $invite = first {
               $_->{type} eq "m.room.member"
                  and $_->{state_key} eq $invitee->user_id
            } @{ $room->{invite_state}{events} };

            assert_json_keys( $invite, qw( sender content state_key type ));
            $invite->{content}{membership} eq "invite"
               or die "Expected an invite event";
            $invite->{sender} eq $user->user_id
               or die "Expected the invite to be from user A";

            Future->done(1);
         });
      })->then_done(1);
   };
