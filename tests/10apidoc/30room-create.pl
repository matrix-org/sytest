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
