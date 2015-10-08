use List::Util qw( first );

my $inviteonly_room_id;

test "A room can be created set to invite-only",
   requires => [qw( user )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user,
         # visibility: "private" actually means join_rule: "invite"
         # See SPEC-74
         visibility => "private",
      )->then( sub {
         ( $inviteonly_room_id ) = @_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$inviteonly_room_id/initialSync",
         )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( state ));

            my ( $join_rules_event ) = first { $_->{type} eq "m.room.join_rules" } @{ $body->{state} };
            $join_rules_event or
               die "Failed to find an m.room.join_rules event";

            $join_rules_event->{content}{join_rule} eq "invite" or
               die "Expected join rule to be 'invite'";

            Future->done(1);
         });
      });
   };

test "Uninvited users cannot join the room",
   requires => [ local_user_preparer() ],

   check => sub {
      my ( $uninvited ) = @_;

      matrix_join_room( $uninvited, $inviteonly_room_id )
         ->main::expect_http_403;
   };

my $invited_user_preparer = local_user_preparer();

test "Can invite users to invite-only rooms",
   requires => [qw( user ), $invited_user_preparer,
                qw( can_invite_room )],

   do => sub {
      my ( $user, $invitee ) = @_;

      matrix_invite_user_to_room( $user, $invitee, $inviteonly_room_id )
   };

test "Invited user receives invite",
   requires => [ $invited_user_preparer,
                 qw( can_invite_room )],

   do => sub {
      my ( $invitee ) = @_;

      await_event_for( $invitee, sub {
         my ( $event ) = @_;

         require_json_keys( $event, qw( type ));
         return 0 unless $event->{type} eq "m.room.member";

         require_json_keys( $event, qw( room_id state_key ));
         return 0 unless $event->{room_id} eq $inviteonly_room_id;
         return 0 unless $event->{state_key} eq $invitee->user_id;

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "invite" or
            die "Expected membership to be 'invite'";

         return 1;
      });
   };

test "Invited user can join the room",
   requires => [ $invited_user_preparer,
                 qw( can_invite_room )],

   do => sub {
      my ( $invitee ) = @_;

      matrix_join_room( $invitee, $inviteonly_room_id )
      ->then( sub {
         matrix_get_room_state( $invitee, $inviteonly_room_id,
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
