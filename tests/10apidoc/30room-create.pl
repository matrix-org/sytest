test "POST /createRoom makes a room",
   requires => [qw( do_request_json_authed can_initial_sync )],

   do => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "POST",
         uri    => "/createRoom",

         content => {
            visibility      => "public",
            # This is just the localpart
            room_alias_name => "#testing-room",
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
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         json_list_ok( $body->{rooms} );
         Future->done( scalar @{ $body->{rooms} } > 0 );
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

test "GET /initialSync sees my presence in the room",
   requires => [qw( do_request_json_authed room_id
                    can_create_room can_initial_sync )],

   check => sub {
      my ( $do_request_json_authed, $room_id ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         my $found;

         json_list_ok( $body->{rooms} );
         foreach my $room ( @{ $body->{rooms} } ) {
            json_keys_ok( $room, qw( room_id membership ));

            next unless $room->{room_id} eq $room_id;
            $found++;

            $room->{membership} eq "join" or die "Expected room membership to be 'join'\n";
            $room->{visibility} eq "public" or die "Expected room visibility to be 'public'\n";
         }

         $found or
            die "Failed to find our newly-joined room";

         Future->done(1);
      });
   };

test "GET /directory/room/:room_alias yields room ID",
   requires => [qw( do_request_json_authed room_alias room_id can_create_room )],

   check => sub {
      my ( $do_request_json_authed, $room_alias, $room_id ) = @_;

      $do_request_json_authed->(
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
