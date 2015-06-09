prepare "Creating special AS user",
   requires => [qw( first_http_client as_credentials )],

   provides => [qw( as_user )],

   do => sub {
      my ( $http, $as_credentials ) = @_;
      my ( $user_id, $token ) = @$as_credentials;

      provide as_user => User( $http, $user_id, $token, undef, [], undef );

      Future->done(1);
   };
