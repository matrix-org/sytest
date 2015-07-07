use List::Util qw( first );

use Crypt::NaCl::Sodium;

my $crypto_sign = Crypt::NaCl::Sodium->sign;

my $json_canon = JSON->new
                     ->convert_blessed
                     ->canonical
                     ->utf8;

test "Federation key API allows unsigned requests for keys",
   requires => [qw( first_home_server http_client )],

   provides => [qw( first_server_key )],

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

         require_json_keys( $body, qw( server_name valid_until_ts signatures verify_keys old_verify_keys tls_fingerprints ));

         require_json_string( $body->{server_name} );
         $body->{server_name} eq $first_home_server or
            die "Expected server_name to be $first_home_server";

         require_json_number( $body->{valid_until_ts} );
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

         require_json_keys( $key, qw( key ));
         $key = $key->{key};

         log_if_fail "Key (base64)", $key;

         $key = require_base64_unpadded_and_decode( $key );

         exists $body->{signatures}{ $body->{server_name} }{$key_id} or
            die "Expected to find a signature by the server's own key";
         my $signature = $body->{signatures}{ $body->{server_name} }{$key_id};

         log_if_fail "Signature (base64)", $signature;

         $signature = require_base64_unpadded_and_decode( $signature );

         my %to_sign = %$body;
         delete $to_sign{signatures};

         my $signed_bytes = $json_canon->encode( \%to_sign );

         log_if_fail "Signed bytes", $signed_bytes ;

         $crypto_sign->verify( $signature, $signed_bytes, $key ) or
            die "Signature verification failed";

         # old_verify_keys is mandatory, even if it's empty
         require_json_object( $body->{old_verify_keys} );

         provide first_server_key => $key;

         Future->done(1);
      });
   };

test "Federation key API can act as a perspective server",
   requires => [qw( first_home_server first_server_key local_server_name inbound_server http_client )],

   check => sub {
      my ( $first_home_server, $server_key, $local_server_name, $inbound_server, $client ) = @_;

      my $key_id = $inbound_server->key_id;

      # TODO: Key API might some day require this to be a signed request.
      $client->do_request_json(
         method => "GET",
         uri    => "https://$first_home_server/_matrix/key/v2/query/$local_server_name/$key_id",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Response", $body;

         require_json_keys( $body, qw( server_keys ));
         require_json_list( $body->{server_keys} );

         my $key = first {
            $_->{server_name} eq $local_server_name and exists $_->{verify_keys}{$key_id}
         } @{ $body->{server_keys} };

         $key or
            die "Expected to find a response about $key_id from $local_server_name";

         exists $key->{signatures}{$first_home_server} or
            die "Expected the key to be signed by the first homeserver";

         my %to_sign = %$key;
         delete $to_sign{signatures};

         # Just presume there's only one signature
         my ( $first_hs_sig ) = values %{ $key->{signatures}{$first_home_server} };
         my $signature = require_base64_unpadded_and_decode( $first_hs_sig );

         my $signed_bytes = $json_canon->encode( \%to_sign );

         $crypto_sign->verify( $signature, $signed_bytes, $server_key ) or
            die "Signature verification failed";

         Future->done(1);
      });
   };
