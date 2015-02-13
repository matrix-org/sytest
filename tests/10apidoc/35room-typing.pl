test "PUT /rooms/:room_id/typing/:user_id sets typing notification",
   requires => [qw( do_request_json room_id
                    can_create_room )],


   provides => [qw( can_set_room_typing )],

   do => sub {
      my ( $do_request_json, $room_id ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/rooms/$room_id/typing/:user_id",

         content => { typing => 1 },
      )->then( sub {
         my ( $body ) = @_;

         # Body is empty

         provide can_set_room_typing => 1;

         Future->done(1);
      });
   };
