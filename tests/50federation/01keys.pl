test "Federation key API allows unsigned requests for keys",
   requires => [qw( first_home_server http_client )],

   check => sub {
      my ( $first_home_server, $client ) = @_;

      # Key API specifically does not require a signed request to ask for the
      # server's own key
      $client->do_request_json(
         method => "GET",
         # TODO: strictly, a valid key ID is required here, but it's hard to
         # know upfront what key IDs exist
         uri => "https://$first_home_server/_matrix/key/v2/server/*",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Key response", $body;

         require_json_keys( $body, qw( server_name valid_until_ts signatures verify_keys tls_fingerprints ));

         require_json_string( $body->{server_name} );
         $body->{server_name} eq $first_home_server or
            die "Expected server_name to be $first_home_server";

         require_json_number( $body->{valid_until_ts} );
         $body->{valid_until_ts} / 1000 > time or
            die "Key valid_until_ts is in the past";

         keys( %{ $body->{verify_keys} } ) > 0 or
            die "Expected to find some verify_keys";

         Future->done(1);
      });
   };
