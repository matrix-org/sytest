use JSON qw( decode_json );

my $user_fixture = local_user_fixture();


test "POST /createRoom makes a public room",
   requires => [ $user_fixture ],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            visibility      => "public",
            # This is just the localpart
            room_alias_name => "30room-create-".time,
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id room_alias ));
         assert_json_nonempty_string( $body->{room_id} );

         Future->done(1);
      });
   };

test "POST /createRoom makes a private room",
   requires => [ $user_fixture ],

   proves => [qw( can_create_private_room )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            visibility => "private",
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));
         assert_json_nonempty_string( $body->{room_id} );

         Future->done(1);
      });
   };

test "POST /createRoom makes a private room with invites",
   requires => [ $user_fixture, local_user_fixture(),
                 qw( can_create_private_room )],

   proves => [qw( can_create_private_room_with_invite )],

   do => sub {
      my ( $user, $invitee ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            visibility => "private",
            invite     => [ $invitee->user_id ],
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));
         assert_json_nonempty_string( $body->{room_id} );

         Future->done(1);
      });
   };

test "POST /createRoom makes a room with a name",
   requires => [ $user_fixture, local_user_fixture(),
                 qw( can_create_private_room )],

   proves => [qw( can_createroom_with_name )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room_synced(
         $user,
         name => 'Test Room',
      )->then( sub {
         my ( $room_id, undef, $body ) = @_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/rooms/$room_id/state/m.room.name",
         )
      })->then( sub {
         my ( $state ) = @_;

         log_if_fail "state", $state;

         assert_json_keys( $state, qw( name ));
         assert_json_nonempty_string( $state->{name} );
         assert_eq( $state->{name}, "Test Room", "room name" );

         Future->done(1);
      });
   };

test "POST /createRoom makes a room with a topic",
   requires => [ $user_fixture, local_user_fixture(),
                 qw( can_create_private_room )],

   proves => [qw( can_createroom_with_topic )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room_synced(
         $user,
         topic => 'Test Room',
      )->then( sub {
         my ( $room_id, undef, $body ) = @_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/rooms/$room_id/state/m.room.topic",
         )
      })->then( sub {
         my ( $state ) = @_;

         log_if_fail "state", $state;

         assert_json_keys( $state, qw( topic ));
         assert_json_nonempty_string( $state->{topic} );
         assert_eq( $state->{topic}, "Test Room", "room topic" );

         Future->done(1);
      });
   };

test "Can /sync newly created room",
   requires => [ $user_fixture ],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room_synced( $user );
   };

test "POST /createRoom creates a room with the given version",
   requires => [ $user_fixture ],
   proves => [qw( can_create_versioned_room )],

   do => sub {
      my ( $user ) = @_;

      my $room_id;

      matrix_create_room_synced(
         $user,
         room_version => '2',
      )->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user );
      })->then( sub {
         my ( $sync_body ) = @_;

         log_if_fail "sync body", $sync_body;

         my $room =  $sync_body->{rooms}{join}{$room_id};
         my $ev0 = $room->{timeline}{events}[0];

         assert_eq( $ev0->{type}, 'm.room.create',
                    'first event was not m.room.create' );
         assert_json_keys( $ev0->{content}, qw( room_version ));
         assert_eq( $ev0->{content}{room_version}, '2', 'room_version' );

         Future->done(1);
      });
   };


test "POST /createRoom rejects attempts to create rooms with numeric versions",
   requires => [ $user_fixture, qw( can_create_versioned_room )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room(
         $user,
         room_version => 1,
      )->main::expect_http_400()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         assert_eq( $body->{errcode}, "M_BAD_JSON", 'responsecode' );
         Future->done( 1 );
      });
   };


test "POST /createRoom rejects attempts to create rooms with unknown versions",
   requires => [ $user_fixture, qw( can_create_versioned_room )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room(
         $user,
         room_version => "agjkyhdsghkjackljkj",
      )->main::expect_http_400()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         assert_eq( $body->{errcode}, "M_UNSUPPORTED_ROOM_VERSION", 'responsecode' );
         Future->done( 1 );
      });
   };

test "POST /createRoom ignores attempts to set the room version via creation_content",
   requires => [ $user_fixture, ],

   do => sub {
      my ( $user ) = @_;

      my $room_id;

      matrix_create_room_synced(
         $user,
         creation_content => {
            test => "azerty",
            room_version => "test",
         },
      )->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user );
      })->then( sub {
         my ( $sync_body ) = @_;

         log_if_fail "sync body", $sync_body;

         my $room =  $sync_body->{rooms}{join}{$room_id};
         my $ev0 = $room->{timeline}{events}[0];

         assert_eq( $ev0->{type}, 'm.room.create',
                    'first event was not m.room.create' );
         assert_json_keys( $ev0->{content}, qw( room_version ));

         # which version we actually get is up to the server impl, so we
         # just check it's not the bogus version we set.
         my $got_ver = $ev0->{content}{room_version};
         defined $got_ver && $got_ver ne 'test' or
            die 'Got unexpected room version $got_ver';

         # check that the rest of creation_content worked
         assert_eq( $ev0->{content}{test}, 'azerty', 'test key' );

         Future->done(1);
      });
   };


=head2 matrix_create_room

   matrix_create_room( $creator, %opts )->then( sub {
      my ( $room_id, $room_alias ) = @_;
   });

Create a new room.

Any options given in %opts are passed into the /createRoom API.

The following options have defaults:

   visibility => 'private'
   preset => 'public_chat'

'room_version' will also be set if an explicit room version was given on the
commandline.

The resultant future completes with two values: the room_id from the
/createRoom response; the room_alias from the /createRoom response (which is
non-standard and its use is deprecated).

=cut

push our @EXPORT, qw( matrix_create_room );

sub matrix_create_room
{
   my ( $user, %opts ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   $opts{visibility} //= "private";
   $opts{preset} //= "public_chat";

   if( defined $TEST_ROOM_VERSION ) {
      $opts{room_version} //= $TEST_ROOM_VERSION;
   }

   do_request_json_for( $user,
      method => "POST",
      uri    => "/r0/createRoom",
      content => \%opts,
   )->then( sub {
      my ( $body ) = @_;

      Future->done( $body->{room_id}, $body->{room_alias} );
   });
}

push @EXPORT, qw( room_alias_name_fixture room_alias_fixture remote_room_alias_fixture matrix_create_room_synced );

my $next_alias_name = 0;

=head2 room_alias_name_fixture

   $fixture = room_alias_name_fixture( prefix => $prefix )

Returns a new Fixture, which when provisioned will allocate a new room alias
name (i.e. localpart, before the homeserver domain name, and return it as a
string.

An optional prefix string can be provided, which will be prepended onto the
alias name.

=cut

sub room_alias_name_fixture
{
   my %args = @_;

   my $prefix = $args{prefix} // "";

   return fixture(
      name => 'room_alias_name_fixture',

      setup => sub {
         my ( $info ) = @_;

         my $alias_name = sprintf "%s__ANON__-%d", $prefix, $next_alias_name++;

         Future->done( $alias_name );
      },
   );
}

=head2 room_alias_fixture

   $fixture = room_alias_fixture( prefix => $prefix, remote => 0 )

Returns a new Fixture, which when provisioned will allocate a name for a new
room alias on the first homeserver, and return it as a string. Note that this
does not actually create the alias on the server itself, it simply suggests a
new unique name for one.

An optional prefix string can be provided, which will be prepended onto the
alias name.

An optional remote boolean can be supplied, which will generate an alias for
the second homeserver instead.

=cut

sub room_alias_fixture
{
   my %args = @_;

   return fixture(
      requires => [
         room_alias_name_fixture( prefix => $args{prefix} ),
         $args{remote} ? $main::HOMESERVER_INFO[1] : $main::HOMESERVER_INFO[0],
      ],

      setup => sub {
         my ( $alias_name, $info ) = @_;

         Future->done( sprintf "#%s:%s", $alias_name, $info->server_name );
      },
   );
}

=head2 remote_room_alias_fixture

   $fixture = remote_room_alias_fixture( prefix => $prefix )

Returns a new Fixture, which when provisioned will allocate a name for a new
room alias on the second homeserver, and return it as a string. Note that this
does not actually create the alias on the server itself, it simply suggests a
new unique name for one.

An optional prefix string can be provided, which will be prepended onto the
alias name.

=cut

sub remote_room_alias_fixture
{
   my %args = @_;

   return room_alias_fixture( prefix => $args{prefix}, remote => 1 );
}


=head2 matrix_create_room_synced

    matrix_create_room_synced( $creator, %params )->then( sub {
        my ( $room_id ) = @_;
    });

Creates a new room, and waits for it to appear in the /sync response.

The parameters are passed through to C<matrix_create_room>.

The resultant future completes with the room_id.

=cut

sub matrix_create_room_synced
{
   my ( $user, %params ) = @_;

   # we want to make sure we have all of the room-creation events before we return.
   # The easiest way to do that is to send a sentinel message in the room and wait for
   # that to turn up.
   matrix_create_room( $user, %params )->then( sub {
      my ( $room_id ) = @_;

      matrix_do_and_wait_for_sync( $user,
         do => sub {
            my $uri = "/r0/rooms/$room_id/send/m.room.test";

            do_request_json_for(
               $user,
               method => "POST",
               uri    => $uri,
               content => {},
            );
         },
         check => sub {
            my ( $sync_body, $send_body ) = @_;
            my $event_id = $send_body->{event_id};
            return sync_timeline_contains( $sync_body, $room_id, sub {
               $_[0]->{event_id} eq $event_id
            });
         },
      )->then_done( $room_id );
   });
}
