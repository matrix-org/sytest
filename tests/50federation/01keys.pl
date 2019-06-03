use List::Util qw( first );

use Crypt::NaCl::Sodium;

use Protocol::Matrix qw( encode_json_for_signing sign_json encode_base64_unpadded );

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
         uri => "https://$first_home_server/_matrix/key/v2/server",
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

sub key_query_via_get {
   my ( $http_client, $notary_server, $origin_server, $key_id ) = @_;

   return $http_client->do_request_json(
      method   => "GET",
      hostname => $notary_server->server_name,
      full_uri => "/_matrix/key/v2/query/$origin_server/$key_id",
   );
}

sub key_query_via_post {
   my ( $http_client, $notary_server, $origin_server, $key_id, %params ) = @_;

   my $min_valid_until_ts = $params{min_valid_until_ts} // 0;

   return $http_client->do_request_json(
      method   => "POST",
      hostname => $notary_server->server_name,
      full_uri => "/_matrix/key/v2/query",
      content  => {
         server_keys => {
            $origin_server => {
               $key_id => {
                  minimum_valid_until_ts => $min_valid_until_ts,
               },
            },
         },
      },
   );
}

my %FETCHERS=(
   GET => \&key_query_via_get,
   POST => \&key_query_via_post,
);

foreach my $method (keys %FETCHERS) {
   test "Federation key API can act as a notary server via a $method request",
      requires => [ $main::HOMESERVER_INFO[0], $main::INBOUND_SERVER, $main::OUTBOUND_CLIENT ],

      check => sub {
         my ( $info, $inbound_server, $client ) = @_;
         my $first_home_server = $info->server_name;

         my $key_id = $inbound_server->key_id;
         my $local_server_name = $inbound_server->server_name;

         $FETCHERS{$method}(
            $client, $info, $local_server_name, $key_id
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
}

# regression test for https://github.com/matrix-org/synapse/issues/5305
test "Key notary server must not overwrite a valid key with a spurious result from the origin server",
   requires => [ $main::HOMESERVER_INFO[0], $main::OUTBOUND_CLIENT, $main::TEST_SERVER_INFO ],

   do => sub {
      my ( $notary_server, $http_client, $http_server ) = @_;
      my $test_server_name = $http_server->server_name;

      # the idea of this test is that we make sure that, even if the origin
      # server forgets about one of its old keys, the notary server does not
      # forget that key (and cannot be made to forget that key by requests from
      # other servers).
      #
      # we use two keys: key_1 is the orignal key, which disappears from the
      # origin server, and key_2, which is just used to sign an itermediate
      # response.

      my ( $pkey1, $skey1 ) = Crypt::NaCl::Sodium->sign->keypair;
      my $key_id_1 = "ed25519:key_1";
      my $key1_expiry = ( time - 86400 ) * 1000; # -24h in msec

      my ( $pkey2, $skey2 ) = Crypt::NaCl::Sodium->sign->keypair;
      my $key_id_2 = "ed25519:key_2";

      # start with a request for key 1
      Future->needs_all(
         await_http_request(
            qr#^/_matrix/key/v2/server#, sub { 1 }
         )->then( sub {
            my ( $request ) = @_;

            log_if_fail "Request 1 from notary server: " . $request->method . " " . $request->path;

            my $key_response1 = {
               server_name => $test_server_name,
               valid_until_ts => $key1_expiry,
               verify_keys => {
                  $key_id_1 => {
                     key => encode_base64_unpadded( $pkey1 ),
                  },
               },
               old_verify_keys => {},
            };
            sign_json(
               $key_response1,
               secret_key => $skey1,
               origin => $test_server_name,
               key_id => $key_id_1,
            );

            $request->respond_json( $key_response1 );
            Future->done(1);
         }),

         key_query_via_post(
            $http_client, $notary_server, $test_server_name, $key_id_1,
         )->then( sub {
            my ( $body ) = @_;
            log_if_fail "Notary response for request 1", $body;

            my $res = $body->{server_keys}[0];
            assert_eq( $res->{server_name}, $test_server_name, "server_name" );
            assert_json_keys( $res->{verify_keys}, ( $key_id_1 ));
            Future->done(1);
         }),
      )->then( sub {
         # now make a second request, with a later min_valid_until_ts, to force a re-fetch,
         # but return a different key to the notary server.
         Future->needs_all(
            await_http_request(
               qr#^/_matrix/key/v2/server#, sub { 1 }
            )->then( sub {
               my ( $request ) = @_;

               log_if_fail "Request 2 from notary server: " . $request->method . " " . $request->path;

               my $key_response2 = {
                  server_name => $test_server_name,
                  valid_until_ts => $key1_expiry + 1000,
                  verify_keys => {
                     $key_id_2 => {
                        key => encode_base64_unpadded( $pkey2 ),
                     },
                  },
                  old_verify_keys => {},
               };
               sign_json(
                  $key_response2,
                  secret_key => $skey2,
                  origin => $test_server_name,
                  key_id => $key_id_2,
                 );

               $request->respond_json( $key_response2 );
               Future->done(1);
            }),

            key_query_via_post(
               $http_client, $notary_server, $test_server_name, $key_id_1,
               min_valid_until_ts => time * 1000,
            )->then( sub {
               my ( $body ) = @_;
               log_if_fail "Notary response for request 2", $body;
               Future->done(1);
            }),
         );
      })->then( sub {
         # finally, make a third request for the key, but with the old min_valid_until_ts,
         # and check it is returned.
         key_query_via_post(
            $http_client, $notary_server, $test_server_name, $key_id_1,
            min_valid_until_ts => $key1_expiry,
         )->then( sub {
            my ( $body ) = @_;
            log_if_fail "Notary response for request 3", $body;

            my $res = $body->{server_keys}[0];
            assert_eq( $res->{server_name}, $test_server_name, "server_name" );
            assert_json_keys( $res->{verify_keys}, ( $key_id_1 ));
            Future->done(1);
         });
      });
   };
