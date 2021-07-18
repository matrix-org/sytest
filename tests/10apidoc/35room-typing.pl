use JSON qw( decode_json );

test "PUT /rooms/:room_id/typing/:user_id sets typing notification",
   requires => [ local_user_and_room_fixtures() ],

   proves => [qw( can_set_room_typing )],

   do => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/rooms/$room_id/typing/:user_id",

         content => {
            typing => JSON::true,
            timeout => 30000,
         },
      )->then( sub {
         my ( $body ) = @_;

         # Body is empty

         Future->done(1);
      });
   };

test "PUT /rooms/:room_id/typing/:user_id without timeout fails",
   requires => [ local_user_and_room_fixtures() ],

   proves => [qw( can_set_room_typing )],

   do => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/rooms/$room_id/typing/:user_id",

         content => { typing => JSON::true },
      )->main::expect_http_400()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         assert_eq( $body->{errcode}, "M_BAD_JSON", 'responsecode' );
         Future->done( 1 );
      });
   };

test "PUT /rooms/:room_id/typing/:user_id with invalid json fails",
   requires => [ local_user_and_room_fixtures() ],

   proves => [qw( can_set_room_typing )],

   do => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/rooms/$room_id/typing/:user_id",

         content => {
            typing => 1,
            timeout => 30000,
         },
      )->main::expect_http_400()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         assert_eq( $body->{errcode}, "M_BAD_JSON", 'responsecode' );
         Future->done( 1 );
      });
   };
