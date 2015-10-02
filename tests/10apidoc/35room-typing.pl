test "PUT /rooms/:room_id/typing/:user_id sets typing notification",
   requires => [qw( user )],

   provides => [qw( can_set_room_typing )],

   do => sub {
      my ( $user ) = @_;

      my $room_id;

      matrix_create_room( $user )
      ->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $user,
            method => "PUT",
            uri    => "/api/v1/rooms/$room_id/typing/:user_id",

            content => { typing => 1 },
         )
      })->then( sub {
         my ( $body ) = @_;

         # Body is empty

         provide can_set_room_typing => 1;

         Future->done(1);
      });
   };
