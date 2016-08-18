test "HS will proxy request for 3PU mapping",
   requires => [ local_user_fixture(), $main::APPSERV[0] ],

   do => sub {
      my ( $user, $appserv ) = @_;

      Future->needs_all(
         $appserv->await_http_request( "/3pu/protocol", sub { 1 } )->then( sub {
            my ( $request ) = @_;

            assert_deeply_eq( { $request->query_form },
               {
                  field1 => "ONE",
                  field2 => "TWO",
               },
            'fields in received AS request' );

            $request->respond_json( [
               {
                  protocol => "protocol",
                  fields => { TODO => "TODO" },
                  userid   => '@remote-user:bridged.example.com',
               }
            ] );

            Future->done(1);
         }),

         do_request_json_for( $user,
            method => "GET",
            uri    => "/unstable/3pu/protocol",

            params => {
               field1 => "ONE",
               field2 => "TWO",
            }
         )->then( sub {
            my ( $body ) = @_;

            log_if_fail "Lookup result", $body;

            assert_deeply_eq( $body, [
               {
                  protocol => "protocol",
                  fields   => { TODO => "TODO" },
                  userid   => '@remote-user:bridged.example.com',
               }
            ], '3PU lookup result' );

            Future->done(1);
         }),
      )
   };
