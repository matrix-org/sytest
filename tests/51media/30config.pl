test "Can read configuration endpoint",
   requires => [ $main::API_CLIENTS[0] ],

   check => sub {
        my ( $http ) = @_;
        $http->do_request(
            method   => "GET",
            full_uri => "/_matrix/media/r0/config",
        )->then( sub {
            my ( $body, $response ) = @_;
                
            assert_json_keys( $body, qw( m.upload.size ) );
            #TODO: We should probably check the size is correct.
            
            Future->done(1);
        });
   };
