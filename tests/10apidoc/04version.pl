test "Version responds 200 OK with valid structure",
   requires => [ $main::API_CLIENTS[0] ],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "GET",
         uri    => "/versions",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( versions ) );
         assert_json_list( $body->{versions} );

         Future->done( 1 );
      })
   };
