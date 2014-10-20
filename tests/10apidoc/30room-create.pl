test "POST /createRoom makes a room",
   requires => [qw( do_request_json_authed can_initial_sync )],

   do => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "POST",
         uri    => "/createRoom",

         content => {
            visibility => "public",
         },
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( room_id ));

         provide can_create_room => 1;
         provide room_id => $body->{room_id};

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

   # Currently this doesn't work - see SYN-106
   expect_fail => 1,

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
