prepare "Creating special AS user",
   requires => [qw( first_http_client as_credentials )],

   provides => [qw( as_user )],

   do => sub {
      my ( $http, $as_credentials ) = @_;
      my ( $user_id, $token ) = @$as_credentials;

      provide as_user => User( $http, $user_id, $token, undef, [], undef );

      Future->done(1);
   };

prepare "Creating test helper functions",
   requires => [qw( await_http_request )],

   provides => [qw( await_as_event )],

   do => sub {
      my ( $await_http_request ) = @_;

      provide await_as_event => sub {
         my ( $type ) = @_;

         $await_http_request->( qr{^/appserv/transactions/\d+$}, sub {
            my ( $body ) = @_;
            $body->{events} and
               grep { $_->{type} eq $type } @{ $body->{events} }
            }
         )->then( sub {
            my ( $body, $request ) = @_;

            # Respond immediately to AS
            $request->respond_json( {} );

            my ( $event ) = grep { $_->{type} eq $type } @{ $body->{events} };
            Future->done( $event );
         });
      };

      Future->done(1);
   };
