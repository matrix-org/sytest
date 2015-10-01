use List::Util qw( first );

test "A room can be created set to invite-only",
   requires => [qw( user )],

   provides => [qw( inviteonly_room_id )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user,
         # visibility: "private" actually means join_rule: "invite"
         # See SPEC-74
         visibility => "private",
      )->then( sub {
         my ( $room_id ) = @_;

         do_request_json_for( $user,
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

            provide inviteonly_room_id => $room_id;

            Future->done(1);
         });
      });
   };

test "Uninvited users cannot join the room",
   requires => [qw( more_users inviteonly_room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $more_users, $room_id ) = @_;
      my $uninvited = $more_users->[0];

      do_request_json_for( $uninvited,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/join",

         content => {},
      )->main::expect_http_403;
   };

test "Can invite users to invite-only rooms",
   requires => [qw( user more_users inviteonly_room_id
                    can_invite_room )],

   do => sub {
      my ( $user, $more_users, $room_id ) = @_;
      my $invitee = $more_users->[1];

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/invite",

         content => { user_id => $invitee->user_id },
      );
   };

test "Invited user receives invite",
   requires => [qw( more_users inviteonly_room_id
                    can_invite_room )],

   await => sub {
      my ( $more_users, $room_id ) = @_;
      my $invitee = $more_users->[1];

      await_event_for( $invitee, sub {
         my ( $event ) = @_;

         require_json_keys( $event, qw( type ));
         return 0 unless $event->{type} eq "m.room.member";

         require_json_keys( $event, qw( room_id state_key ));
         return 0 unless $event->{room_id} eq $room_id;
         return 0 unless $event->{state_key} eq $invitee->user_id;

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "invite" or
            die "Expected membership to be 'invite'";

         return 1;
      });
   };

test "Invited user can join the room",
   requires => [qw( more_users inviteonly_room_id
                    can_invite_room can_join_room_by_id )],

   do => sub {
      my ( $more_users, $room_id ) = @_;
      my $invitee = $more_users->[1];

      do_request_json_for( $invitee,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/join",

         content => {},
      )->then( sub {
         do_request_json_for( $invitee,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state/m.room.member/${\$invitee->user_id}",
         )
      })->then( sub {
         my ( $member_state ) = @_;

         $member_state->{membership} eq "join" or
            die "Expected my membership to be 'join'";

         Future->done(1);
      });
   };

test "Banned user is kicked and may not rejoin",
   requires => [qw( user more_users room_id
                    can_ban_room )],

   do => sub {
      my ( $user, $more_users, $room_id ) = @_;
      my $banned_user = $more_users->[0];

      # Pre-test assertion that the user we want to ban is present
      do_request_json_for( $banned_user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.member/${\$banned_user->user_id}",
      )->then( sub {
         my ( $body ) = @_;
         $body->{membership} eq "join" or
            die "Pretest assertion failed: expected user to be in 'join' state";

         do_request_json_for( $user,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/ban",

            content => { user_id => $banned_user->user_id, reason => "testing" },
         );
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state/m.room.member/${\$banned_user->user_id}",
         );
      })->then( sub {
         my ( $body ) = @_;
         $body->{membership} eq "ban" or
            die "Expected banned user membership to be 'ban'";

         do_request_json_for( $banned_user,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/join",

            content => {},
         )
      })->main::expect_http_403;
   };
