test "POST /createRoom makes a public room",
   requires => [qw( user can_initial_sync )],

   provides => [qw( room_id room_alias )],

   critical => 1,

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/createRoom",

         content => {
            visibility      => "public",
            # This is just the localpart
            room_alias_name => "testing-room",
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id room_alias ));
         require_json_nonempty_string( $body->{room_id} );
         require_json_nonempty_string( $body->{room_alias} );

         provide room_id    => $body->{room_id};
         provide room_alias => $body->{room_alias};

         Future->done(1);
      });
   },

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_list( $body->{rooms} );
         Future->done( scalar @{ $body->{rooms} } > 0 );
      });
   };

test "GET /rooms/:room_id/state/m.room.member/:user_id fetches my membership",
   requires => [qw( user room_id )],

   provides => [qw( can_get_room_membership )],

   check => sub {
      my ( $user, $room_id ) = @_;

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
   requires => [qw( user room_id )],

   provides => [qw( can_get_room_powerlevels )],

   check => sub {
      my ( $user, $room_id ) = @_;

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
   requires => [qw( user room_id )],

   provides => [qw( can_room_initial_sync )],

   check => sub {
      my ( $user, $room_id ) = @_;

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
   requires => [qw( first_api_client room_id )],

   check => sub {
      my ( $http, $room_id ) = @_;

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
   requires => [qw( user room_alias room_id )],

   check => sub {
      my ( $user, $room_alias, $room_id ) = @_;

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

# Other forms of /createRoom
test "POST /createRoom makes a private room",
   requires => [qw( user )],

   provides => [qw( can_create_private_room )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/createRoom",

         content => {
            visibility => "private",
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id ));
         require_json_nonempty_string( $body->{room_id} );

         provide can_create_private_room => 1;

         Future->done(1);
      });
   };

test "POST /createRoom makes a private room with invites",
   requires => [qw( user more_users
                    can_create_private_room )],

   provides => [qw( can_create_private_room_with_invite )],

   do => sub {
      my ( $user, $more_users ) = @_;
      my $invitee = $more_users->[0];

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/createRoom",

         content => {
            visibility => "private",
            # TODO: This doesn't actually appear in the API docs yet
            invite     => [ $invitee->user_id ],
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id ));
         require_json_nonempty_string( $body->{room_id} );

         provide can_create_private_room_with_invite => 1;

         Future->done(1);
      });
   };

push our @EXPORT, qw( matrix_create_room );

sub matrix_create_room
{
   my ( $user, %opts ) = @_;

   do_request_json_for( $user,
      method => "POST",
      uri    => "/api/v1/createRoom",

      content => {
         visibility => $opts{visibility} || "public",
         ( defined $opts{room_alias_name} ?
            ( room_alias_name => $opts{room_alias_name} ) : () ),
         ( defined $opts{invite} ?
            ( invite => $opts{invite} ) : () ),
      }
   )->then( sub {
      my ( $body ) = @_;

      Future->done( $body->{room_id}, $body->{room_alias} );
   });
}
