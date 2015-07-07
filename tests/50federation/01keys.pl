use Crypt::NaCl::Sodium;
use MIME::Base64 qw( decode_base64 );

my $crypto_sign = Crypt::NaCl::Sodium->sign;

my $json_canon = JSON->new
                     ->convert_blessed
                     ->canonical
                     ->utf8;

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

         $key =~ m([^A-Za-z0-9+/=]) and
            die "Key contains invalid base64 characters";
         $key =~ m(=) and
            die "Key contains trailing padding";
         $key = decode_base64( $key );

         exists $body->{signatures}{ $body->{server_name} }{$key_id} or
            die "Expected to find a signature by the server's own key";
         my $signature = $body->{signatures}{ $body->{server_name} }{$key_id};

         log_if_fail "Signature (base64)", $signature;

         $signature =~ m([^A-Za-z0-9+/=]) and
            die "Signature contains invalid base64 characters";
         $signature =~ m(=) and
            die "Signature contains trailing padding";
         $signature = decode_base64( $signature );

         my %to_sign = %$body;
         delete $to_sign{signatures};

         my $signed_bytes = $json_canon->encode( \%to_sign );

         log_if_fail "Signed bytes", $signed_bytes ;

         $crypto_sign->verify( $signature, $signed_bytes, $key ) or
            die "Signature verification failed";

         Future->done(1);
      });
   };
