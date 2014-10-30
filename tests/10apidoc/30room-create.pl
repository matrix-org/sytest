test "POST /createRoom makes a room",
   requires => [qw( do_request_json can_initial_sync )],

   do => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "POST",
         uri    => "/createRoom",

         content => {
            visibility      => "public",
            # This is just the localpart
            room_alias_name => "testing-room",
         },
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( room_id room_alias ));
         json_nonempty_string_ok( $body->{room_id} );
         json_nonempty_string_ok( $body->{room_alias} );

         provide can_create_room => 1;
         provide room_id    => $body->{room_id};
         provide room_alias => $body->{room_alias};

         Future->done(1);
      });
   },

   check => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         json_list_ok( $body->{rooms} );
         Future->done( scalar @{ $body->{rooms} } > 0 );
      });
   };

test "GET /rooms/:room_id/state/m.room.member/:user_id fetches my membership",
   requires => [qw( do_request_json room_id can_create_room )],

   check => sub {
      my ( $do_request_json, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.member/:user_id",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( membership ));

         $body->{membership} eq "join" or
            die "Expected membership as 'join'";

         Future->done(1);
      });
   };

test "GET /publicRooms lists newly-created room",
   requires => [qw( first_http_client room_id can_create_room )],

   check => sub {
      my ( $http, $room_id ) = @_;

      $http->do_request_json(
         method => "GET",
         uri    => "/publicRooms",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( start end chunk ));
         json_list_ok( $body->{chunk} );

         my $found;

         foreach my $event ( @{ $body->{chunk} } ) {
            json_keys_ok( $event, qw( room_id ));
            next unless $event->{room_id} eq $room_id;

            $found = 1;
         }

         $found or
            die "Failed to find our newly-created room";

         Future->done(1);
      })
   };

test "GET /directory/room/:room_alias yields room ID",
   requires => [qw( do_request_json room_alias room_id can_create_room )],

   check => sub {
      my ( $do_request_json, $room_alias, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( room_id servers ));
         json_list_ok( $body->{servers} );

         $body->{room_id} eq $room_id or die "Expected room_id";

         Future->done(1);
      });
   };
