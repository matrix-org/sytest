use List::Util qw( first );

my $creator_fixture = local_user_fixture();

sub inviteonly_room_fixture
{
   my %args = @_;

   fixture(
      requires => [ $args{creator} ],

      setup => sub {
         my ( $creator ) = @_;

         matrix_create_room( $creator,
            # visibility: "private" actually means join_rule: "invite"
            # See SPEC-74
            visibility => "private",
         )->then( sub {
            my ( $room_id ) = @_;

            do_request_json_for( $creator,
               method => "GET",
               uri    => "/api/v1/rooms/$room_id/initialSync",
            )->then( sub {
               my ( $body ) = @_;

               require_json_keys( $body, qw( state ));

               my ( $join_rules_event ) = first { $_->{type} eq "m.room.join_rules" } @{ $body->{state} };
               $join_rules_event or
                  die "Failed to find an m.room.join_rules event";

               $join_rules_event->{content}{join_rule} eq "invite" or
                  die "Expected join rule to be 'invite'";

               Future->done( $room_id );
            });
         });
      }
   )
};

multi_test "Can invite users to invite-only rooms",
   requires => [ $creator_fixture, local_user_fixture(),
                 inviteonly_room_fixture( creator => $creator_fixture ),
                 qw( can_invite_room )],

   do => sub {
      my ( $creator, $invitee, $room_id ) = @_;

      matrix_invite_user_to_room( $creator, $invitee, $room_id )
         ->SyTest::pass_on_done( "Sent invite" )
      ->then( sub {
         await_event_for( $invitee, sub {
            my ( $event ) = @_;

            require_json_keys( $event, qw( type ));
            return 0 unless $event->{type} eq "m.room.member";

            require_json_keys( $event, qw( room_id state_key ));
            return 0 unless $event->{room_id} eq $room_id;
            return 0 unless $event->{state_key} eq $invitee->user_id;

            return 1;
         })
      })->then( sub {
         my ( $event ) = @_;

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "invite" or
            die "Expected membership to be 'invite'";

         pass "Received invite";

         matrix_join_room( $invitee, $room_id )
            ->SyTest::pass_on_done( "Joined room" )
      })->then( sub {
         matrix_get_room_state( $invitee, $room_id,
            type      => "m.room.member",
            state_key => $invitee->user_id,
         )
      })->then( sub {
         my ( $member_state ) = @_;

         $member_state->{membership} eq "join" or
            die "Expected my membership to be 'join'";

         Future->done(1);
      });
   };

test "Uninvited users cannot join the room",
   requires => [ local_user_fixture(),
                 inviteonly_room_fixture( creator => $creator_fixture ) ],

   check => sub {
      my ( $uninvited, $room_id ) = @_;

      matrix_join_room( $uninvited, $room_id )
         ->main::expect_http_403;
   };

my $other_local_user_fixture = local_user_fixture();

test "Invited user can reject invite",
   requires => [ local_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
   } ],
   do => \&invited_user_can_reject_invite;

test "Invited user can reject invite over federation",
   requires => [ remote_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
   } ],
   do => \&invited_user_can_reject_invite;

sub invited_user_can_reject_invite
{
   my ( $invitee, $creator, $room_id ) = @_;

   matrix_invite_user_to_room( $creator, $invitee, $room_id )
   ->then( sub {
      matrix_leave_room( $invitee, $room_id )
   })->then( sub {
      matrix_get_room_state( $creator, $room_id,
         type      => "m.room.member",
         state_key => $invitee->user_id,
      );
   })->then( sub {
      my ( $body ) = @_;

      log_if_fail "Membership body", $body;
      $body->{membership} eq "leave" or
         die "Expected membership to be 'leave'";

      Future->done(1);
   });
}
