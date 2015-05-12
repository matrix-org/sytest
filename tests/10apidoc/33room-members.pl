test "POST /rooms/:room_id/join can join a room",
   requires => [qw( do_request_json_for more_users room_id
                    can_get_room_membership )],

   provides => [qw( can_join_room_by_id )],

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

   provides => [qw( can_join_room_by_alias )],

   do => sub {
      my ( $do_request_json_for, $more_users, $room_id, $room_alias ) = @_;
      my $user = $more_users->[1];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/join/$room_alias",

         content => {},
      )->then( sub {
         my ( $body ) = @_;

         $body->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id";

         Future->done(1);
      });
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

test "POST /join/:room_id can join a room",
   requires => [qw( do_request_json_for more_users room_id
                    can_get_room_membership )],

   do => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $user = $more_users->[2];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/join/$room_id",

         content => {},
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id ));
         $body->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id";

         Future->done(1);
      });
   },

   check => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $user = $more_users->[2];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.member/:user_id",
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "join" or
            die "Expected membership to be 'join'";

         Future->done(1);
      });
   };

test "POST /rooms/:room_id/leave can leave a room",
   requires => [qw( do_request_json_for more_users room_id
                    can_join_room_by_id can_get_room_membership )],

   provides => [qw( can_leave_room )],

   do => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $user = $more_users->[1];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/rooms/$room_id/leave",

         content => {},
      );
   },

   check => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $user = $more_users->[1];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.member/:user_id",
      )->then(
         sub { # then
            my ( $body ) = @_;

            $body->{membership} eq "join" and
               die "Expected membership not to be 'join'";

            provide can_leave_room => 1;

            Future->done(1);
         },
         sub { # else
            my ( $failure, $name, $response ) = @_;
            Future->fail( @_ ) unless defined $name and $name eq "http";
            Future->fail( @_ ) unless $response->code == 403;

            # We're expecting a 403 so that's fine
            provide can_leave_room => 1;

            Future->done(1);
         },
      );
   };

test "POST /rooms/:room_id/invite can send an invite",
   requires => [qw( do_request_json_for user more_users room_id
                    can_get_room_membership )],

   provides => [qw( can_invite_room )],

   do => sub {
      my ( $do_request_json_for, $user, $more_users, $room_id ) = @_;
      my $invitee = $more_users->[1];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/rooms/$room_id/invite",

         content => { user_id => $invitee->user_id },
      );
   },

   check => sub {
      my ( $do_request_json_for, $user, $more_users, $room_id ) = @_;
      my $invitee = $more_users->[1];

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

test "POST /rooms/:room_id/ban can ban a user",
   requires => [qw( do_request_json_for user more_users room_id
                    can_get_room_membership )],

   provides => [qw( can_ban_room )],

   do => sub {
      my ( $do_request_json_for, $user, $more_users, $room_id ) = @_;
      my $banned_user = $more_users->[2];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => "/rooms/$room_id/ban",

         content => {
            user_id => $banned_user->user_id,
            reason  => "Just testing",
         },
      );
   },

   check => sub {
      my ( $do_request_json_for, $user, $more_users, $room_id ) = @_;
      my $banned_user = $more_users->[2];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.member/" . $banned_user->user_id,
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "ban" or
            die "Expecting membership to be 'ban'";

         provide can_ban_room => 1;

         Future->done(1);
      });
   };

my $next_alias = 1;

prepare "Creating test-room-creation helper function",
   requires => [qw( do_request_json_for await_event_for
                    can_create_room can_join_room_by_alias )],

   provides => [qw( make_test_room )],

   do => sub {
      my ( $do_request_json_for, $await_event_for ) = @_;

      provide make_test_room => sub {
         my ( $creator, @other_members ) = @_;

         my $room_id;
         my $room_alias_shortname = "test-$next_alias"; $next_alias++;

         my ( $domain ) = $creator->user_id =~ m/:(.*)$/;
         my $room_alias_fullname = "#${room_alias_shortname}:$domain";

         my $n_joiners = scalar @other_members;

         $do_request_json_for->( $creator,
            method => "POST",
            uri    => "/createRoom",

            content => {
               visibility      => "public",
               room_alias_name => $room_alias_shortname,
            },
         )->then( sub {
            my ( $body ) = @_;
            $room_id = $body->{room_id};

            log_if_fail "room_id=$room_id";

            Future->needs_all( map {
               my $user = $_;
               $do_request_json_for->( $user,
                  method => "POST",
                  uri    => "/join/$room_alias_fullname",

                  content => {},
               )
            } @other_members )
         })->then( sub {
            return Future->done( $room_id ) unless $n_joiners;

            # Now wait for the creator to see every join event, so we're sure
            # the remote joins have happened
            my %joined_members;

            $await_event_for->( $creator, sub {
               my ( $event ) = @_;
               log_if_fail "Creator event", $event;

               return unless $event->{type} eq "m.room.member";
               return unless $event->{room_id} eq $room_id;

               $joined_members{$event->{state_key}}++;

               return 1 if keys( %joined_members ) == $n_joiners;
               return 0;
            })->then_done( $room_id );
         })
      };

      Future->done;
   };
