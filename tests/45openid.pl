test "Can generate a openid access_token that can be exchanged for information about a user",
   requires => [ local_user_fixture(), $main::HTTP_CLIENT, $main::HOMESERVER_INFO[0] ],

   check => sub {
      my ( $user, $http, $info ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/r0/user/:user_id/openid/token",
         content => {},
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( access_token matrix_server_name expires_in ) );
         assert_eq( $body->{matrix_server_name}, $info->server_name );

         my $token = $body->{access_token};

         $http->do_request_json(
            method   => "GET",
            uri => $info->client_location . "/_matrix/federation/v1/openid/userinfo",
            params   => { access_token => $token },
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( sub ) );
         assert_eq( $body->{sub}, $user->user_id );

         Future->done(1);
      });
   };

test "Invalid openid access tokens are rejected",
   requires => [ $main::HTTP_CLIENT, $main::HOMESERVER_INFO[0] ],

   check => sub {
      my ( $http, $info ) = @_;

      $http->do_request_json(
         method   => "GET",
         uri => $info->client_location . "/_matrix/federation/v1/openid/userinfo",
         params   => { access_token => "an/invalid/token" },
      )->main::expect_http_401;
   };

test "Requests to userinfo without access tokens are rejected",
   requires => [ $main::HTTP_CLIENT, $main::HOMESERVER_INFO[0] ],

   check => sub {
      my ( $http, $info ) = @_;

      $http->do_request_json(
         method   => "GET",
         uri => $info->client_location . "/_matrix/federation/v1/openid/userinfo",
      )->main::expect_http_401;
   };
