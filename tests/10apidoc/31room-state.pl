use List::Util qw( any );
use List::UtilsBy qw( partition_by );

my $name = "room name here";

my $user_fixture = local_user_fixture();

# This provides $room_id *AND* $room_alias
my $room_fixture = fixture(
   name => 'room_fixture',

   requires => [ $user_fixture, room_alias_name_fixture() ],

   setup => sub {
      my ( $user, $room_alias_name ) = @_;

      matrix_create_room( $user,
         room_alias_name => $room_alias_name,
         visibility      => "public",
      );
   },
);

test "GET /rooms/:room_id/state/m.room.member/:user_id fetches my membership",
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_get_room_membership )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/rooms/$room_id/state/m.room.member/:user_id",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( membership ));

         assert_eq( $body->{membership}, "join", 'body.membership' );

         # This shouldn't look like an event
         exists $body->{$_} and die "Did not expect to find a '$_' key"
            for qw( sender event_id room_id );

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state/m.room.member/:user_id?format=event fetches my membership event",
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_get_room_membership )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/rooms/$room_id/state/m.room.member/:user_id",
         params => {
            format => "event",
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( sender room_id content ));

         assert_eq( $body->{sender}, $user->user_id, 'event.sender' );
         assert_eq( $body->{room_id}, $room_id,      'event.room_id' );

         my $content = $body->{content};
         assert_json_keys( $content, qw( membership ));

         assert_eq( $content->{membership}, "join", 'content.membership' );

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state/m.room.power_levels fetches powerlevels",
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_get_room_power_levels )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/rooms/$room_id/state/m.room.power_levels",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( ban kick redact users_default
            state_default events_default users events ));

         assert_json_object( $body->{users} );
         assert_json_object( $body->{events} );

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/joined_members fetches my membership",
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_get_room_joined_members )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/rooms/$room_id/joined_members",
      )->then( sub {
         my ( $body ) = @_;

         log_if_fail "joined_members", $body;

         assert_json_keys( $body, qw( joined ));

         my $members = $body->{joined};
         assert_json_object( $members->{ $user->user_id } );

         my $myself = $members->{ $user->user_id };

         # We always have these keys even if they're undef
         assert_json_keys( $myself, qw( display_name avatar_url ));

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/initialSync fetches initial sync state",
   deprecated_endpoints => 1,
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_room_initial_sync )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      matrix_initialsync_room( $user, $room_id )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id membership state messages presence ));
         assert_json_keys( $body->{messages}, qw( chunk start end ));
         assert_json_list( $body->{messages}{chunk} );
         assert_json_list( $body->{state} );
         assert_json_list( $body->{presence} );

         $body->{room_id} eq $room_id or
            die "Expected 'room_id' as $room_id";
         $body->{membership} eq "join" or
            die "Expected 'membership' as 'join'";

         Future->done(1);
      });
   };

test "GET /publicRooms lists newly-created room",
   requires => [ $main::API_CLIENTS[0], $room_fixture ],

   check => sub {
      my ( $http, $room_id, undef ) = @_;

      $http->do_request_json(
         method => "GET",
         uri    => "/r0/publicRooms",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ));
         assert_json_list( $body->{chunk} );

         my $found;

         foreach my $event ( @{ $body->{chunk} } ) {
            assert_json_keys( $event, qw( room_id ));
            next unless $event->{room_id} eq $room_id;

            $found = 1;
         }

         $found or
            die "Failed to find our newly-created room";

         Future->done(1);
      })
   };

test "GET /directory/room/:room_alias yields room ID",
   requires => [ $main::SPYGLASS_USER, $room_fixture ],

   check => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id servers ));
         assert_json_list( $body->{servers} );

         $body->{room_id} eq $room_id or die "Expected room_id";

         Future->done(1);
      });
   };

test "GET /joined_rooms lists newly-created room",
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_get_joined_rooms )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/joined_rooms",
      )->then( sub {
         my ( $body ) = @_;

         log_if_fail "joined_rooms", $body;

         assert_json_keys( $body, qw( joined_rooms ));
         assert_json_list( my $roomlist = $body->{joined_rooms} );

         assert_ok( ( any { $_ eq $room_id } @$roomlist ),
            'room_id found in joined_rooms list'
         );

         Future->done(1);
      });
   };

test "POST /rooms/:room_id/state/m.room.name sets name",
   requires => [ $user_fixture, $room_fixture],

   proves => [qw( can_set_room_name )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/rooms/$room_id/state/m.room.name",

         content => { name => $name },
      )->then( sub {
         await_sync_timeline_contains($user, $room_id,
            check => sub {
               my ( $event ) = @_;
               return $event->{type} eq "m.room.name" &&
                  $event->{state_key} eq "" &&
                  $event->{content}{name} eq $name;
            },
         )
      })
   };

test "GET /rooms/:room_id/state/m.room.name gets name",
   requires => [ $user_fixture, $room_fixture,
                 qw( can_set_room_name )],

   proves => [qw( can_get_room_name )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/rooms/$room_id/state/m.room.name",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( name ));

         $body->{name} eq $name or
            die "Expected name to be '$name'";

         Future->done(1);
      });
   };

my $topic = "A new topic for the room";

test "POST /rooms/:room_id/state/m.room.topic sets topic",
   requires => [ $user_fixture, $room_fixture],

   proves => [qw( can_set_room_topic )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/rooms/$room_id/state/m.room.topic",

         content => { topic => $topic },
      )->then( sub {
         await_sync_timeline_contains($user, $room_id,
            check => sub {
               my ( $event ) = @_;
               return $event->{type} eq "m.room.topic" &&
                  $event->{state_key} eq "" &&
                  $event->{content}{topic} eq $topic;
            },
         )
      })
   };

test "GET /rooms/:room_id/state/m.room.topic gets topic",
   requires => [ $user_fixture, $room_fixture,
                 qw( can_set_room_topic )],

   proves => [qw( can_get_room_topic )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/rooms/$room_id/state/m.room.topic",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( topic ));

         $body->{topic} eq $topic or
            die "Expected topic to be '$topic'";

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state fetches entire room state",
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_get_room_all_state )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/rooms/$room_id/state",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_list( $body );

         my %state_by_type = partition_by { $_->{type} } @$body;

         defined $state_by_type{$_} or die "Missing $_ state" for
            qw( m.room.create m.room.join_rules m.room.name m.room.power_levels );

         Future->done(1);
      });
   };

# This test is best deferred to here, so we can fetch the state

test "POST /createRoom with creation content",
   requires => [ $user_fixture ],

   proves => [qw( can_create_room_with_creation_content )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            creation_content => {
               "m.federate" => JSON::false,
            },
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));
         assert_json_nonempty_string( my $room_id = $body->{room_id} );

         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/rooms/$room_id/state/m.room.create",
         )
      })->then( sub {
         my ( $state ) = @_;

         log_if_fail "state", $state;

         assert_json_keys( $state, qw( m.federate ));

         Future->done(1);
      });
   };

push our @EXPORT, qw(
   matrix_get_room_state matrix_put_room_state matrix_get_my_member_event
   matrix_initialsync_room matrix_put_room_state_synced
);

sub matrix_get_room_state
{
   my ( $user, $room_id, %opts ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   defined $opts{state_key} and not defined $opts{type} and
      croak "Cannot matrix_get_room_state() with a state_key but no type";

   do_request_json_for( $user,
      method => "GET",
      uri    => join( "/",
         "/r0/rooms/$room_id/state", grep { defined } $opts{type}, $opts{state_key}
      ),
   );
}

=head2 matrix_get_room_state_by_type

    matrix_get_room_state_by_type( $user, $room_id, %opts )->then( sub {
       my ( $state ) = @_;
       my $event = $state->{'m.room.member'}->{$user_id};
    });

Makes a /room/<room_id>/state request. Returns a map from type to state_key to
event.

The following may be passed as optional parameters:

=over

=item type => STRING

the type of state to fetch

=item state_key => STRING

the state_key to fetch

=cut

sub matrix_get_room_state_by_type
{
   my ( $user, $room_id, %opts ) = @_;
   matrix_get_room_state( $user, $room_id, %opts ) -> then( sub {
      my ( $state ) = @_;

      my %state_by_type;
      for my $ev (@$state) {
         my $type = $ev->{type};
         my $state_key = $ev->{state_key};
         $state_by_type{$type} //= {};

         die "duplicate state key $type:$state_key in /state response"
            if exists $state_by_type{$type}->{$state_key};

         $state_by_type{$type}->{$state_key} = $ev;
      }
      Future->done( \%state_by_type );
   });
}
push @EXPORT, qw( matrix_get_room_state_by_type );

sub matrix_put_room_state
{
   my ( $user, $room_id, %opts ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   defined $opts{state_key} and not defined $opts{type} and
      croak "Cannot matrix_put_room_state() with a state_key but no type";

   defined $opts{content} or
      croak "Cannot matrix_put_room_state() with no content";

   do_request_json_for( $user,
      method => "PUT",
      uri    => join( "/",
         "/r0/rooms/$room_id/state", grep { defined } $opts{type}, $opts{state_key}
      ),

      content => $opts{content},
   );
}

sub matrix_get_my_member_event
{
   my ( $user, $room_id ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   # TODO: currently have to go the long way around finding it; see SPEC-264
   matrix_get_room_state( $user, $room_id )->then( sub {
      my ( $state ) = @_;

      my $member_event = first {
         $_->{type} eq "m.room.member" and $_->{state_key} eq $user->user_id
      } @$state;

      Future->done( $member_event );
   });
}

sub matrix_initialsync_room
{
   my ( $user, $room_id, %params ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/r0/rooms/$room_id/initialSync",
      params => \%params,
   );
}


sub matrix_put_room_state_synced
{
   my ( $user, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_put_room_state( $user, $room_id, %params );
      },
      check => sub {
         my ( $sync_body, $put_result ) = @_;
         my $event_id = $put_result->{event_id};

         sync_timeline_contains( $sync_body, $room_id, sub {
            $_[0]->{event_id} eq $event_id;
         });
      },
   );
}
