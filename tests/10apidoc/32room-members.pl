test "POST /rooms/:room_id/join can join a room",
   requires => [qw( do_request_json_for more_users room_id
                    can_get_room_membership )],

   do => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $user = $more_users->[0];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/rooms/$room_id/join",

         content => {},
      );
   },

   check => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $user = $more_users->[0];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.member/:user_id",
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "join" or
            die "Expected membership to be 'join'";

         provide can_join_room_by_id => 1;

         Future->done(1);
      });
   };

test "POST /join/:room_alias can join a room",
   requires => [qw( do_request_json_for more_users room_id room_alias
                    can_get_room_membership )],

   do => sub {
      my ( $do_request_json_for, $more_users, undef, $room_alias ) = @_;
      my $user = $more_users->[1];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/join/$room_alias",
         params => { access_token => $user->access_token },

         content => {},
      );
   },

   check => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $user = $more_users->[1];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.member/:user_id",
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "join" or
            die "Expected membership to be 'join'";

         provide can_join_room_by_alias => 1;

         Future->done(1);
      });
   };

test "POST /rooms/:room_id/invite can send an invite",
   requires => [qw( do_request_json_for user more_users room_id
                    can_get_room_membership )],

   do => sub {
      my ( $do_request_json_for, $user, $more_users, $room_id ) = @_;
      my $invitee = $more_users->[2];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/rooms/$room_id/invite",

         content => { user_id => $invitee->user_id },
      );
   },

   check => sub {
      my ( $do_request_json_for, $user, $more_users, $room_id ) = @_;
      my $invitee = $more_users->[2];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.member/" . $invitee->user_id,
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "invite" or
            die "Expected membership to be 'invite'";

         provide can_invite_room => 1;

         Future->done(1);
      });
   };

test "POST /rooms/:room_id/leave can leave a room",
   requires => [qw( do_request_json_for more_users room_id
                    can_join_room_by_id can_get_room_membership )],

   do => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $user = $more_users->[0];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/rooms/$room_id/leave",

         content => {},
      );
   },

   check => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $user = $more_users->[0];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.member/:user_id",
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "join" and
            die "Expected membership not to be 'join'";

         provide can_leave_room => 1;

         Future->done(1);
      });
   };
