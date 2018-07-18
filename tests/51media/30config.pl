test "Can read configuration endpoint",
   requires => [ $main::API_CLIENTS[0] ],

   check => sub {
        my ( $http ) = @_;
        $http->do_request_json(
            method   => "GET",
            full_uri => "/_matrix/media/r0/config",
        )->then( sub {
            my ( $body ) = @_;

            # TODO: Check size is correct
            if ( defined $body->{"m.upload.size"} ) {
                assert_json_number( $body->{"m.upload.size"} )
            }
            
            Future->done(1);
        });
   };
