use Future::Utils qw( fmap );
use List::UtilsBy qw( partition_by );

my $room_id;
my $room_alias;

prepare "Creating testing room",
   requires => [qw( user )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user,
         room_alias_name => "33room-members",
      )->on_done( sub {
         ( $room_id, $room_alias ) = @_;
      });
   };

test "POST /rooms/:room_id/join can join a room",
   requires => [qw( more_users
                    can_get_room_membership )],

   critical => 1,

   do => sub {
      my ( $more_users ) = @_;
      my $user = $more_users->[0];

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/join",

         content => {},
      );
   },

   check => sub {
      my ( $more_users ) = @_;
      my $user = $more_users->[0];

      matrix_get_room_state( $user, $room_id,
         type      => "m.room.member",
         state_key => $user->user_id,
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "join" or
            die "Expected membership to be 'join'";

         Future->done(1);
      });
   };

push our @EXPORT, qw( matrix_join_room );

sub matrix_join_room
{
   my ( $user, $room_id ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   do_request_json_for( $user,
      method => "POST",
      uri    => "/api/v1/rooms/$room_id/join",

      content => {},
   )->then_done(1);
}

test "POST /join/:room_alias can join a room",
   requires => [qw( more_users
                    can_get_room_membership )],

   provides => [qw( can_join_room_by_alias )],

   do => sub {
      my ( $more_users ) = @_;
      my $user = $more_users->[1];

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/join/$room_alias",

         content => {},
      )->then( sub {
         my ( $body ) = @_;

         $body->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id";

         Future->done(1);
      });
   },

   check => sub {
      my ( $more_users ) = @_;
      my $user = $more_users->[1];

      matrix_get_room_state( $user, $room_id,
         type      => "m.room.member",
         state_key => $user->user_id,
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "join" or
            die "Expected membership to be 'join'";

         provide can_join_room_by_alias => 1;

         Future->done(1);
      });
   };

test "POST /join/:room_id can join a room",
   requires => [qw( more_users
                    can_get_room_membership )],

   do => sub {
      my ( $more_users ) = @_;
      my $user = $more_users->[2];

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/join/$room_id",

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
      my ( $more_users ) = @_;
      my $user = $more_users->[2];

      matrix_get_room_state( $user, $room_id,
         type      => "m.room.member",
         state_key => $user->user_id,
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "join" or
            die "Expected membership to be 'join'";

         Future->done(1);
      });
   };

test "POST /rooms/:room_id/leave can leave a room",
   requires => [qw( more_users
                    can_get_room_membership )],

   critical => 1,

   do => sub {
      my ( $more_users ) = @_;
      my $user = $more_users->[1];

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/leave",

         content => {},
      );
   },

   check => sub {
      my ( $more_users ) = @_;
      my $user = $more_users->[1];

      matrix_get_room_state( $user, $room_id,
         type      => "m.room.member",
         state_key => $user->user_id,
      )->then(
         sub { # then
            my ( $body ) = @_;

            $body->{membership} eq "join" and
               die "Expected membership not to be 'join'";

            Future->done(1);
         },
         sub { # else
            my ( $failure, $name, $response ) = @_;
            Future->fail( @_ ) unless defined $name and $name eq "http";
            Future->fail( @_ ) unless $response->code == 403;

            # We're expecting a 403 so that's fine

            Future->done(1);
         },
      );
   };

push @EXPORT, qw( matrix_leave_room );

sub matrix_leave_room
{
   my ( $user, $room_id ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   do_request_json_for( $user,
      method => "POST",
      uri    => "/api/v1/rooms/$room_id/leave",

      content => {},
   )->then_done(1);
}

test "POST /rooms/:room_id/invite can send an invite",
   requires => [qw( user more_users
                    can_get_room_membership )],

   provides => [qw( can_invite_room )],

   do => sub {
      my ( $user, $more_users ) = @_;
      my $invitee = $more_users->[1];

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/invite",

         content => { user_id => $invitee->user_id },
      );
   },

   check => sub {
      my ( $user, $more_users ) = @_;
      my $invitee = $more_users->[1];

      matrix_get_room_state( $user, $room_id,
         type      => "m.room.member",
         state_key => $invitee->user_id,
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "invite" or
            die "Expected membership to be 'invite'";

         provide can_invite_room => 1;

         push our @EXPORT, qw( matrix_invite_user_to_room );

         Future->done(1);
      });
   };

sub matrix_invite_user_to_room
{
   my ( $user, $invitee, $room_id ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   my $invitee_id;
   if( is_User( $invitee ) ) {
      $invitee_id = $invitee->user_id;
   }
   elsif( !ref $invitee ) {
      $invitee_id = $invitee;
   }
   else {
      croak "Expected invitee to be a User struct or plain string; got $invitee";
   }

   do_request_json_for( $user,
      method => "POST",
      uri    => "/api/v1/rooms/$room_id/invite",

      content => { user_id => $invitee_id }
   )->then_done(1);
}

test "POST /rooms/:room_id/ban can ban a user",
   requires => [qw( user more_users
                    can_get_room_membership )],

   provides => [qw( can_ban_room )],

   do => sub {
      my ( $user, $more_users ) = @_;
      my $banned_user = $more_users->[2];

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/ban",

         content => {
            user_id => $banned_user->user_id,
            reason  => "Just testing",
         },
      );
   },

   check => sub {
      my ( $user, $more_users ) = @_;
      my $banned_user = $more_users->[2];

      matrix_get_room_state( $user, $room_id,
         type      => "m.room.member",
         state_key => $banned_user->user_id,
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
   requires => [qw( can_join_room_by_alias )],

   provides => [qw( make_test_room )],

   do => sub {
      provide make_test_room => sub {
         my ( $members, %options ) = @_;
         my ( $creator, @other_members ) = @$members;

         is_User( $creator ) or croak "Expected a User for creator; got $creator";

         is_User( $_ ) or croak "Expected a User for a member; got $_"
            for @other_members;

         my $room_id;
         my $room_alias_fullname;

         my $n_joiners = scalar @other_members;

         matrix_create_room( $creator,
            %options,
            room_alias_name => sprintf( "test-%d", $next_alias++ ),
         )->then( sub {
            ( $room_id, $room_alias_fullname ) = @_;

            log_if_fail "room_id=$room_id";

            # Best not to join remote users concurrently because of
            #   https://matrix.org/jira/browse/SYN-318
            my %members_by_server = partition_by { $_->http } @other_members;

            my @local_members = @{ delete $members_by_server{ $creator->http } // [] };
            my @remote_members = map { @$_ } values %members_by_server;

            Future->needs_all(
               ( fmap {
                  my $user = shift;
                  do_request_json_for( $user,
                     method => "POST",
                     uri    => "/api/v1/join/$room_alias_fullname",

                     content => {},
                  )
               } foreach => \@remote_members ),

               map {
                  my $user = $_;
                  do_request_json_for( $user,
                     method => "POST",
                     uri    => "/api/v1/join/$room_alias_fullname",

                     content => {},
                  )
               } @local_members )
         })->then( sub {
            return Future->done( $room_id ) unless $n_joiners;

            # Now wait for the creator to see every join event, so we're sure
            # the remote joins have happened
            my %joined_members;

            await_event_for( $creator, sub {
               my ( $event ) = @_;
               log_if_fail "Creator event", $event;

               return unless $event->{type} eq "m.room.member";
               return unless $event->{room_id} eq $room_id;

               $joined_members{ $event->{state_key} }++;

               return 1 if keys( %joined_members ) == $n_joiners;
               return 0;
            })->then_done( $room_id );
         })
      };

      Future->done;
   };
