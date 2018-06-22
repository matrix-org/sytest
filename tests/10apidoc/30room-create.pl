my $user_fixture = local_user_fixture();


test "POST /createRoom makes a public room",
   requires => [ $user_fixture ],

   critical => 1,

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            visibility      => "public",
            # This is just the localpart
            room_alias_name => "30room-create",
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id room_alias ));
         assert_json_nonempty_string( $body->{room_id} );
         assert_json_nonempty_string( $body->{room_alias} );

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

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            name => "Test Room"
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));
         assert_json_nonempty_string( $body->{room_id} );

         my ( $room_id ) = $body->{room_id};

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

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            topic => "Test Room"
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));
         assert_json_nonempty_string( $body->{room_id} );

         my ( $room_id ) = $body->{room_id};

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

test "POST /createRoom makes a room with guest access enabled",
   requires => [ $user_fixture, local_user_fixture(),
                 qw( can_create_private_room )],

   proves => [qw( can_createroom_with_guest_access )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            guest_can_join => JSON::true
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));
         assert_json_nonempty_string( $body->{room_id} );

         my ( $room_id ) = $body->{room_id};

         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/rooms/$room_id/state/m.room.guest_access",
         )
      })->then( sub {
         my ( $state ) = @_;

         log_if_fail "state", $state;

         assert_json_keys( $state, qw( guest_access ));
         assert_json_nonempty_string( $state->{guest_access} );
         assert_eq( $state->{guest_access}, "can_join", "room guest access policy" );

         Future->done(1);
      });
   };

test "POST /createRoom makes a room with guest access disabled",
   requires => [ $user_fixture, local_user_fixture(),
                 qw( can_create_private_room )],

   proves => [qw( can_createroom_with_guest_access )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            guest_can_join => JSON::false
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));
         assert_json_nonempty_string( $body->{room_id} );

         my ( $room_id ) = $body->{room_id};

         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/rooms/$room_id/state/m.room.guest_access",
         )
      })->then( sub {
         my ( $state ) = @_;

         log_if_fail "state", $state;

         assert_json_keys( $state, qw( guest_access ));
         assert_json_nonempty_string( $state->{guest_access} );
         assert_eq( $state->{guest_access}, "forbidden", "room guest access policy" );

         Future->done(1);
      });
   };

test "Can /sync newly created room",
   requires => [ $user_fixture ],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room_synced( $user );
   };

push our @EXPORT, qw( matrix_create_room );

sub matrix_create_room
{
   my ( $user, %opts ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   do_request_json_for( $user,
      method => "POST",
      uri    => "/r0/createRoom",

      content => {
         visibility => $opts{visibility} || "private",
         preset     => $opts{preset} || "public_chat",
         ( defined $opts{room_alias_name} ?
            ( room_alias_name => $opts{room_alias_name} ) : () ),
         ( defined $opts{invite} ?
            ( invite => $opts{invite} ) : () ),
         ( defined $opts{invite_3pid} ?
            ( invite_3pid => $opts{invite_3pid} ) : () ),
         ( defined $opts{creation_content} ?
            ( creation_content => $opts{creation_content} ) : () ),
         ( defined $opts{name} ?
            ( name => $opts{name} ) : () ),
         ( defined $opts{topic} ?
            ( topic => $opts{topic} ) : () ),
      }
   )->then( sub {
      my ( $body ) = @_;

      Future->done( $body->{room_id}, $body->{room_alias} );
   });
}

push @EXPORT, qw( room_alias_name_fixture room_alias_fixture matrix_create_room_synced );

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

   $fixture = room_alias_fixture( prefix => $prefix )

Returns a new Fixture, which when provisioned will allocate a name for a new
room alias on the first homeserver, and return it as a string. Note that this
does not actually create the alias on the server itself, it simply suggests a
new unique name for one.

An optional prefix string can be provided, which will be prepended onto the
alias name.

=cut

sub room_alias_fixture
{
   my %args = @_;

   return fixture(
      requires => [
         room_alias_name_fixture( prefix => $args{prefix} ), $main::HOMESERVER_INFO[0],
      ],

      setup => sub {
         my ( $alias_name, $info ) = @_;

         Future->done( sprintf "#%s:%s", $alias_name, $info->server_name );
      },
   );
}


sub matrix_create_room_synced
{
   my ( $user, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_create_room( $user, %params );
      },
      check => sub { exists $_[0]->{rooms}{join}{$_[1]} },
   );
}
