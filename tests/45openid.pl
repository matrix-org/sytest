test "Can generate a openid access_token that can be exchanged for information about a user",
   requires => [ local_user_fixture(), $main::HOMESERVER_INFO[0] ],

   check => sub {
      my ( $user, $info ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/r0/user/:user_id/openid/token",
         content => {},
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( access_token matrix_server_name expires_in ) );
         assert_eq( $body->{matrix_server_name}, $info->server_name );

         my $token = $body->{access_token};

         $user->http->do_request_json(
            method   => "GET",
            full_uri => $info->client_location . "/_matrix/federation/v1/openid/userinfo",
            params   => { access_token => $token },
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( sub ) );
         assert_eq( $body->{sub}, $user->user_id );

         Future->done(1);
      });
   };
