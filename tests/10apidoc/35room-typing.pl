test "PUT /rooms/:room_id/typing/:user_id sets typing notification",
   requires => [ local_user_and_room_fixtures() ],

   proves => [qw( can_set_room_typing )],

   do => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/typing/:user_id",

         content => { typing => 1 },
      )->then( sub {
         my ( $body ) = @_;

         # Body is empty

         Future->done(1);
      });
   };
