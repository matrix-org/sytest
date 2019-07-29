use Future 0.33; # then catch semantics
use Future::Utils qw( fmap );
use List::UtilsBy qw( partition_by );

my $creator_fixture = local_user_fixture();

# This provides $room_id *AND* $room_alias
my $room_fixture = fixture(
   requires => [ $creator_fixture, room_alias_name_fixture() ],

   setup => sub {
      my ( $user, $room_alias_name ) = @_;

      matrix_create_room( $user,
         room_alias_name => $room_alias_name,
      );
   },
);

test "POST /rooms/:room_id/join can join a room",
   requires => [ local_user_fixture(), $room_fixture,
                 qw( can_get_room_membership )],

   do => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/rooms/$room_id/join",

         content => {},
      )->then( sub {
         my ( $body ) = @_;

         $body->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id";

         # Retry getting the state a few times, as it may take some time to
         # propagate in a multi-process homeserver
         retry_until_success {
            matrix_get_room_state( $user, $room_id,
               type      => "m.room.member",
               state_key => $user->user_id,
            )->then( sub {
               my ( $body ) = @_;

               $body->{membership} eq "join" or
                  die "Expected membership to be 'join'";

               Future->done(1);
            })
         }
      });
   };

push our @EXPORT, qw( matrix_join_room );

sub matrix_join_room
{
   my ( $user, $room, %opts ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   my %content;

   defined $opts{third_party_signed} and $content{third_party_signed} = $opts{third_party_signed};

   do_request_json_for( $user,
      method => "POST",
      uri    => "/r0/join/$room",

      content => \%content,
   )->then( sub {
      my ( $body ) = @_;

      my $user_id = $user->user_id;
      log_if_fail "User $user_id joined room", $body;

      Future->done( $body->{room_id} )
   });
}

test "POST /join/:room_alias can join a room",
   requires => [ local_user_fixture(), $room_fixture,
                 qw( can_get_room_membership )],

   proves => [qw( can_join_room_by_alias )],

   do => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/join/$room_alias",

         content => {},
      )->then( sub {
         my ( $body ) = @_;

         $body->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id";

         # Retry getting the state a few times, as it may take some time to
         # propagate in a multi-process homeserver
         retry_until_success {
            matrix_get_room_state( $user, $room_id,
               type      => "m.room.member",
               state_key => $user->user_id,
            )->then( sub {
               my ( $body ) = @_;

               $body->{membership} eq "join" or
                  die "Expected membership to be 'join'";

               Future->done(1);
            })
         }
      });
   };

test "POST /join/:room_id can join a room",
   requires => [ local_user_fixture(), $room_fixture,
                 qw( can_get_room_membership )],

   do => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/join/$room_id",

         content => {},
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));
         $body->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id";

         # Retry getting the state a few times, as it may take some time to
         # propagate in a multi-process homeserver
         retry_until_success {
            matrix_get_room_state( $user, $room_id,
               type      => "m.room.member",
               state_key => $user->user_id,
            )->then( sub {
               my ( $body ) = @_;

               $body->{membership} eq "join" or
                  die "Expected membership to be 'join'";

               Future->done(1);
            })
         }
      });
   };

test "POST /join/:room_id can join a room with custom content",
   requires => [ local_user_fixture(), $room_fixture,
                 qw( can_get_room_membership )],

   do => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/join/$room_id",

         content => { "foo" => "bar" },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ) );
         assert_eq( $body->{room_id}, $room_id );

         # Retry getting the state a few times, as it may take some time to
         # propagate in a multi-process homeserver
         retry_until_success {
            matrix_get_room_state( $user, $room_id,
               type      => "m.room.member",
               state_key => $user->user_id,
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "body", $body;

               assert_json_keys( $body, qw( foo membership ) );
               assert_eq( $body->{foo}, "bar" );
               assert_eq( $body->{membership}, "join" );

               Future->done(1);
            })
         }
      });
   };

test "POST /join/:room_alias can join a room with custom content",
   requires => [ local_user_fixture(), $room_fixture,
                 qw( can_get_room_membership )],

   do => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/join/$room_alias",

         content => { "foo" => "bar" },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ) );
         assert_eq( $body->{room_id}, $room_id );

         # Retry getting the state a few times, as it may take some time to
         # propagate in a multi-process homeserver
         retry_until_success {
            matrix_get_room_state( $user, $room_id,
               type      => "m.room.member",
               state_key => $user->user_id,
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "body", $body;

               assert_json_keys( $body, qw( foo membership ) );
               assert_eq( $body->{foo}, "bar" );
               assert_eq( $body->{membership}, "join" );

               Future->done(1);
            })
         }
      });
   };

test "POST /rooms/:room_id/leave can leave a room",
   requires => [ local_user_fixture(), $room_fixture,
                 qw( can_get_room_membership )],

   do => sub {
      my ( $joiner_to_leave, $room_id, undef ) = @_;

      matrix_join_room( $joiner_to_leave, $room_id )
      ->then( sub {
         do_request_json_for( $joiner_to_leave,
            method => "POST",
            uri    => "/r0/rooms/$room_id/leave",

            content => {},
         )
      })->then( sub {
         # Retry getting the state a few times, as it may take some time to
         # propagate in a multi-process homeserver
         retry_until_success {
            matrix_get_room_state( $joiner_to_leave, $room_id,
               type      => "m.room.member",
               state_key => $joiner_to_leave->user_id,
            )->then( sub { # then
               my ( $body ) = @_;

               $body->{membership} eq "join" and
                  die "Expected membership not to be 'join'";

               Future->done(1);
            },
            http => sub { # catch
               my ( $failure, undef, $response ) = @_;
               Future->fail( @_ ) unless $response->code == 403;

               # We're expecting a 403 so that's fine

               Future->done(1);
            })
         }
      });
   };

push @EXPORT, qw( matrix_leave_room );

sub matrix_leave_room
{
   my ( $user, $room_id ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   do_request_json_for( $user,
      method => "POST",
      uri    => "/r0/rooms/$room_id/leave",

      content => {},
   )->then_done(1);
}

test "POST /rooms/:room_id/invite can send an invite",
   requires => [ $creator_fixture, local_user_fixture(), $room_fixture,
                 qw( can_get_room_membership )],

   proves => [qw( can_invite_room )],

   do => sub {
      my ( $creator, $invited_user, $room_id, undef ) = @_;

      do_request_json_for( $creator,
         method => "POST",
         uri    => "/r0/rooms/$room_id/invite",

         content => { user_id => $invited_user->user_id },
      )->then( sub {
         # Retry getting the state a few times, as it may take some time to
         # propagate in a multi-process homeserver
         retry_until_success {
            matrix_get_room_state( $creator, $room_id,
               type      => "m.room.member",
               state_key => $invited_user->user_id,
            )->then( sub {
               my ( $body ) = @_;

               $body->{membership} eq "invite" or
                  die "Expected membership to be 'invite'";

               Future->done(1);
            })
         }
      });
   };

push @EXPORT, qw( matrix_invite_user_to_room );

sub matrix_invite_user_to_room
{
   my ( $user, $invitee, $room_id ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";
   ( defined $room_id and !ref $room_id ) or croak "Expected a room ID; got $room_id";

   my $invitee_id;
   if( is_User( $invitee ) ) {
      $invitee_id = $invitee->user_id;
   }
   elsif( defined $invitee and !ref $invitee ) {
      $invitee_id = $invitee;
   }
   else {
      croak "Expected invitee to be a User struct or plain string; got $invitee";
   }

   do_request_json_for( $user,
      method => "POST",
      uri    => "/r0/rooms/$room_id/invite",

      content => { user_id => $invitee_id }
   )->then( sub {
      my ( $body ) = @_;
      log_if_fail "Invited user $invitee_id to $room_id", $body;
      Future->done(1);
   });
}

test "POST /rooms/:room_id/ban can ban a user",
   requires => [ $creator_fixture, local_user_fixture(), $room_fixture,
                 qw( can_get_room_membership )],

   proves => [qw( can_ban_room )],

   do => sub {
      my ( $creator, $banned_user, $room_id, undef ) = @_;

      do_request_json_for( $creator,
         method => "POST",
         uri    => "/r0/rooms/$room_id/ban",

         content => {
            user_id => $banned_user->user_id,
            reason  => "Just testing",
         },
      )->then( sub {
         # Retry getting the state a few times, as it may take some time to
         # propagate in a multi-process homeserver
         retry_until_success {
            matrix_get_room_state( $creator, $room_id,
               type      => "m.room.member",
               state_key => $banned_user->user_id,
            )->then( sub {
               my ( $body ) = @_;

               $body->{membership} eq "ban" or
                  die "Expecting membership to be 'ban'";

               Future->done(1);
            })
         }
      });
   };

my $next_alias = 1;

sub _invite_users
{
   my ( $creator, $room_id, @other_members ) = @_;

   Future->needs_all(
     ( map {
         my $user = $_;
         matrix_invite_user_to_room( $creator, $user, $room_id );
      } @other_members)
   );
}

=head2 matrix_create_and_join_room

   matrix_create_and_join_room( [ $creator, $user2, ... ], %opts )->then( sub {
      my ( $room_id ) = @_;
   });

   matrix_create_and_join_room( [ $creator, $user2, ... ],
     with_alias => 1, %opts,
   )->then( sub {
      my ( $room_id, $room_alias ) = @_;
   });

Create a new room, and have a list of users join it.

The following may be passed as optional parametrs:

=over

=item with_alias => SCALAR

Make this truthy to return the newly created alias

=item with_invite => SCALAR

Make this truthy to send invites to the other users before they join.

=item (everything else)

Other parameters are passed into C<matrix_create_room>, whence they are
passed on to the server.

=back

=cut

push @EXPORT, qw( matrix_create_and_join_room );

sub matrix_create_and_join_room
{
   my ( $members, %options ) = @_;
   my ( $creator, @other_members ) = @$members;

   is_User( $creator ) or croak "Expected a User for creator; got $creator";

   is_User( $_ ) or croak "Expected a User for a member; got $_"
      for @other_members;

   my $room_id;

   my $n_joiners = scalar @other_members;

   my $creator_server_name = $creator->http->server_name;
   my $room_alias_name = sprintf "test-%s-%d", $TEST_RUN_ID, $next_alias++;
   my $room_alias_fullname =
      sprintf "#%s:%s", $room_alias_name, $creator_server_name;

   my $with_invite = delete $options{with_invite};
   my $with_alias = delete $options{with_alias};

   matrix_create_room( $creator,
      %options,
      room_alias_name => $room_alias_name,
   )->then( sub {
      ( $room_id ) = @_;

      log_if_fail "room_id=$room_id";

      ( $with_invite ?
         _invite_users( $creator, $room_id, @other_members ) :
         Future->done() )
   })->then( sub {
      # Best not to join remote users concurrently because of
      #   https://matrix.org/jira/browse/SYN-318
      my %members_by_server = partition_by { $_->http } @other_members;

      my @local_members = @{ delete $members_by_server{ $creator->http } // [] };
      my @remote_members = map { @$_ } values %members_by_server;

      Future->needs_all(
         ( fmap {
            my $user = shift;
            matrix_join_room_synced( $user, $room_alias_fullname )
         } foreach => \@remote_members ),

         map {
            my $user = $_;
            matrix_join_room_synced( $user, $room_alias_fullname )
         } @local_members,
      )
   })->then( sub {
      Future->done( $room_id,
         ( $with_alias ? ( $room_alias_fullname ) : () )
      );
   });
}

=head2 room_fixture

   $fixture = room_fixture( $user_fixture, %opts );

Returns a Fixture, which when provisioned will create a new room on the user's
server and return the room id.

C<$user_fixture> should be a Fixture which will provide a User when
provisioned.

Any other options are passed into C<matrix_create_room>, whence they are passed
on to the server.

It is generally easier to use C<local_user_and_room_fixtures>.

=cut

push @EXPORT, qw( room_fixture );

sub room_fixture
{
   my ( $user_fixture, %args ) = @_;

   fixture(
      requires => [ $user_fixture ],

      setup => sub {
         my ( $user ) = @_;

         matrix_create_room( $user, %args )->then( sub {
            my ( $room_id ) = @_;
            # matrix_create_room returns the room_id and the room_alias if
            #  one was set. However we only want to return the room_id
            #  because our callers only expect the room_id to be passed to
            #  their setup code.
            Future->done( $room_id );
         });
      }
   );
}

push @EXPORT, qw( magic_room_fixture );

sub magic_room_fixture
{
   my %args = @_;

   fixture(
      requires => delete $args{requires_users},

      setup => sub {
         my @members = @_;

         matrix_create_and_join_room( \@members, %args );
      }
   );
}

=head2 local_user_and_room_fixtures

   ( $user_fixture, $room_fixture ) = local_user_and_room_fixtures( %opts );

Returns a pair of Fixtures, which when provisioned will respectively create a
new user on the main test server (returning the User object), and use that
user to create a new room (returning the room id).

The following can be passed as optional parameters:

=over

=item user_opts => HASH

Options to use when creating the user, such as C<displayname>. These are passed
through to C<setup_user>.

=item room_opts => HASH

Options to use when creating the room. Thes are passed into into
C<matrix_create_room>, whence they are passed on to the server.

=back

=cut

push @EXPORT, qw( local_user_and_room_fixtures );

sub local_user_and_room_fixtures
{
   my %args = @_;

   my $user_opts = $args{user_opts} // {};
   my $room_opts = $args{room_opts} // {};

   my $user_fixture = local_user_fixture( %$user_opts );

   return (
      $user_fixture,
      room_fixture( $user_fixture, %$room_opts ),
   );
}

push @EXPORT, qw(
   magic_local_user_and_room_fixtures matrix_join_room_synced
   matrix_leave_room_synced matrix_invite_user_to_room_synced
);

sub magic_local_user_and_room_fixtures
{
   my %args = @_;

   my $user_fixture = local_user_fixture();

   return (
      $user_fixture,
      magic_room_fixture( requires_users => [ $user_fixture ], %args ),
   );
}

sub matrix_join_room_synced
{
   my ( $user, $room_id_or_alias, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_join_room( $user, $room_id_or_alias, %params );
      },
      check => sub { exists $_[0]->{rooms}{join}{$_[1]} },
   );
}

sub matrix_leave_room_synced
{
   my ( $user, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_leave_room( $user, $room_id, %params );
      },
      check => sub { exists $_[0]->{rooms}{leave}{$room_id} },
   );
}

sub matrix_invite_user_to_room_synced
{
   my ( $inviter, $invitee, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $inviter,
      do => sub {
         matrix_do_and_wait_for_sync( $invitee,
            do => sub {
               matrix_invite_user_to_room(
                  $inviter, $invitee, $room_id, %params
               );
            },
            check => sub { exists $_[0]->{rooms}{invite}{$room_id} },
         );
      },
      check => sub {
         sync_timeline_contains( $_[0], $room_id, sub {
            $_[0]->{type} eq "m.room.member"
               and $_[0]->{state_key} eq $invitee->user_id
               and $_[0]->{content}{membership} eq "invite"
         });
      },
   );
}
