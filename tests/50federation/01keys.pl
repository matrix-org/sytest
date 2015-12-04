use List::Util qw( first );

use Crypt::NaCl::Sodium;

use Protocol::Matrix qw( encode_json_for_signing );

my $crypto_sign = Crypt::NaCl::Sodium->sign;

test "Federation key API allows unsigned requests for keys",
   requires => [ $main::HOMESERVER_INFO[0], $main::HTTP_CLIENT ],

   check => sub {
      my ( $info, $client ) = @_;
      my $first_home_server = $info->server_name;

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

         assert_json_keys( $body, qw( server_name valid_until_ts signatures verify_keys old_verify_keys tls_fingerprints ));

         assert_json_string( $body->{server_name} );
         $body->{server_name} eq $first_home_server or
            die "Expected server_name to be $first_home_server";

         assert_json_number( $body->{valid_until_ts} );
         $body->{valid_until_ts} / 1000 > time or
            die "Key valid_until_ts is in the past";

         keys( %{ $body->{verify_keys} } ) > 0 or
            die "Expected to find some verify_keys";

         # TODO: Currently test synapses only ever give us one key, and it's
         # an ed25519. This test will need expanding with fancier logic if
         # that ever changes.
         keys( %{ $body->{verify_keys} } ) == 1 or
            die "TODO - this test cannot cope with more than one verification key";
         my ( $key_id, $key ) = %{ $body->{verify_keys} };
         $key_id =~ m/^ed25519:/ or
            die "TODO - this test cannot cope with verification key algorithms that are not ed25519";

         assert_json_keys( $key, qw( key ));
         $key = $key->{key};

         log_if_fail "Key (base64)", $key;

         assert_base64_unpadded( $key );
         $key = decode_base64 $key;

         exists $body->{signatures}{ $body->{server_name} }{$key_id} or
            die "Expected to find a signature by the server's own key";
         my $signature = $body->{signatures}{ $body->{server_name} }{$key_id};

         log_if_fail "Signature (base64)", $signature;

         assert_base64_unpadded( $signature );
         $signature = decode_base64 $signature;

         my $signed_bytes = encode_json_for_signing( $body );

         log_if_fail "Signed bytes", $signed_bytes ;

         $crypto_sign->verify( $signature, $signed_bytes, $key ) or
            die "Signature verification failed";

         # old_verify_keys is mandatory, even if it's empty
         assert_json_object( $body->{old_verify_keys} );

         Future->done(1);
      });
   };

test "Federation key API can act as a notary server",
   requires => [ $main::HOMESERVER_INFO[0], $main::INBOUND_SERVER, $main::OUTBOUND_CLIENT ],

   check => sub {
      my ( $info, $inbound_server, $client ) = @_;
      my $first_home_server = $info->server_name;

      my $key_id = $inbound_server->key_id;
      my $local_server_name = $inbound_server->server_name;

      $client->do_request_json(
         method   => "GET",
         hostname => $first_home_server,
         full_uri => "/_matrix/key/v2/query/$local_server_name/$key_id",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Response", $body;

         assert_json_keys( $body, qw( server_keys ));
         assert_json_list( $body->{server_keys} );

         my $key = first {
            $_->{server_name} eq $local_server_name and exists $_->{verify_keys}{$key_id}
         } @{ $body->{server_keys} };

         $key or
            die "Expected to find a response about $key_id from $local_server_name";

         my $first_hs_sig = $key->{signatures}{$first_home_server} or
            die "Expected the key to be signed by the first homeserver";

         keys %$first_hs_sig == 1 or
            die "Expected the first homeserver to apply one signature";

         my ( $key_id, $signature_base64 ) = %$first_hs_sig;

         assert_base64_unpadded( $signature_base64 );
         my $signature = decode_base64 $signature_base64;

         my $signed_bytes = encode_json_for_signing( $key );

         $client->get_key(
            server_name => $first_home_server,
            key_id      => $key_id,
         )->then( sub {
            my ( $server_key ) = @_;

            $crypto_sign->verify( $signature, $signed_bytes, $server_key ) or
               die "Signature verification failed";

            Future->done(1);
         });
      });
   };
