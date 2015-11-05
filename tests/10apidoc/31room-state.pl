use List::UtilsBy qw( partition_by );

my $name = "room name here";

my $user_preparer = local_user_preparer();

# This provides $room_id *AND* $room_alias
my $room_preparer = preparer(
   requires => [ $user_preparer ],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user,
         room_alias_name => "31room-state",
      );
   },
);

test "GET /rooms/:room_id/state/m.room.member/:user_id fetches my membership",
   requires => [ $user_preparer, $room_preparer ],

   provides => [qw( can_get_room_membership )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.member/:user_id",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( membership ));

         $body->{membership} eq "join" or
            die "Expected membership as 'join'";

         provide can_get_room_membership => 1;

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state/m.room.power_levels fetches powerlevels",
   requires => [ $user_preparer, $room_preparer ],

   provides => [qw( can_get_room_powerlevels )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.power_levels",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( ban kick redact users_default
            state_default events_default users events ));

         require_json_object( $body->{users} );
         require_json_object( $body->{events} );

         provide can_get_room_powerlevels => 1;

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/initialSync fetches initial sync state",
   requires => [ $user_preparer, $room_preparer ],

   provides => [qw( can_room_initial_sync )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id membership state messages presence ));
         require_json_keys( $body->{messages}, qw( chunk start end ));
         require_json_list( $body->{messages}{chunk} );
         require_json_list( $body->{state} );
         require_json_list( $body->{presence} );

         $body->{room_id} eq $room_id or
            die "Expected 'room_id' as $room_id";
         $body->{membership} eq "join" or
            die "Expected 'membership' as 'join'";

         provide can_room_initial_sync => 1;

         Future->done(1);
      });
   };

test "GET /publicRooms lists newly-created room",
   requires => [qw( first_api_client ), $room_preparer ],

   check => sub {
      my ( $http, $room_id, undef ) = @_;

      $http->do_request_json(
         method => "GET",
         uri    => "/api/v1/publicRooms",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( start end chunk ));
         require_json_list( $body->{chunk} );

         my $found;

         foreach my $event ( @{ $body->{chunk} } ) {
            require_json_keys( $event, qw( room_id ));
            next unless $event->{room_id} eq $room_id;

            $found = 1;
         }

         $found or
            die "Failed to find our newly-created room";

         Future->done(1);
      })
   };

test "GET /directory/room/:room_alias yields room ID",
   requires => [ our $SPYGLASS_USER, $room_preparer ],

   check => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id servers ));
         require_json_list( $body->{servers} );

         $body->{room_id} eq $room_id or die "Expected room_id";

         Future->done(1);
      });
   };

test "POST /rooms/:room_id/state/m.room.name sets name",
   requires => [ $user_preparer, $room_preparer,
                 qw( can_room_initial_sync )],

   provides => [qw( can_set_room_name )],

   do => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/state/m.room.name",

         content => { name => $name },
      );
   },

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( state ));
         my $state = $body->{state};

         my %state_by_type = partition_by { $_->{type} } @$state;

         $state_by_type{"m.room.name"} or
            die "Expected to find m.room.name state";

         provide can_set_room_name => 1;

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state/m.room.name gets name",
   requires => [ $user_preparer, $room_preparer,
                 qw( can_set_room_name )],

   provides => [qw( can_get_room_name )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.name",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( name ));

         $body->{name} eq $name or
            die "Expected name to be '$name'";

         provide can_get_room_name => 1;

         Future->done(1);
      });
   };

my $topic = "A new topic for the room";

test "POST /rooms/:room_id/state/m.room.topic sets topic",
   requires => [ $user_preparer, $room_preparer,
                 qw( can_room_initial_sync )],

   provides => [qw( can_set_room_topic )],

   do => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/state/m.room.topic",

         content => { topic => $topic },
      );
   },

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( state ));
         my $state = $body->{state};

         my %state_by_type = partition_by { $_->{type} } @$state;

         $state_by_type{"m.room.topic"} or
            die "Expected to find m.room.topic state";

         provide can_set_room_topic => 1;

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state/m.room.topic gets topic",
   requires => [ $user_preparer, $room_preparer,
                 qw( can_set_room_topic )],

   provides => [qw( can_get_room_topic )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.topic",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( topic ));

         $body->{topic} eq $topic or
            die "Expected topic to be '$topic'";

         provide can_get_room_topic => 1;

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state fetches entire room state",
   requires => [ $user_preparer, $room_preparer ],

   provides => [qw( can_get_room_all_state )],

   check => sub {
      my ( $user, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state",
      )->then( sub {
         my ( $body ) = @_;

         require_json_list( $body );

         my %state_by_type = partition_by { $_->{type} } @$body;

         defined $state_by_type{$_} or die "Missing $_ state" for
            qw( m.room.create m.room.join_rules m.room.name m.room.power_levels );

         provide can_get_room_all_state => 1;

         Future->done(1);
      });
   };

# This test is best deferred to here, so we can fetch the state

test "POST /createRoom with creation content",
   requires => [ $user_preparer ],

   provides => [qw( can_create_room_with_creation_content )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/createRoom",

         content => {
            creation_content => {
               "m.federate" => JSON::true,
            },
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id ));
         require_json_nonempty_string( my $room_id = $body->{room_id} );

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state/m.room.create",
         )
      })->then( sub {
         my ( $state ) = @_;

         log_if_fail "state", $state;

         require_json_keys( $state, qw( m.federate ));

         provide can_create_room_with_creation_content => 1;

         Future->done(1);
      });
   };

push our @EXPORT, qw( matrix_get_room_state matrix_put_room_state );

sub matrix_get_room_state
{
   my ( $user, $room_id, %opts ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   defined $opts{state_key} and not defined $opts{type} and
      croak "Cannot matrix_get_room_state() with a state_key but no type";

   do_request_json_for( $user,
      method => "GET",
      uri    => join( "/",
         "/api/v1/rooms/$room_id/state", grep { defined } $opts{type}, $opts{state_key}
      ),
   );
}

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
         "/api/v1/rooms/$room_id/state", grep { defined } $opts{type}, $opts{state_key}
      ),

      content => $opts{content},
   );
}
