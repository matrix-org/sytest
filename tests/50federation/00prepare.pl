use File::Basename qw( dirname );

use IO::Socket::IP 0.04; # ->sockhostname
Net::Async::HTTP->VERSION( '0.39' ); # ->GET with 'headers'

use Crypt::NaCl::Sodium;

use SyTest::Federation::Client;
use SyTest::Federation::Server;

my $DIR = dirname( __FILE__ );

struct FederationParams => [qw( server_name key_id public_key secret_key )];

prepare "Creating inbound federation HTTP server and outbound federation client",
   provides => [qw( inbound_server outbound_client )],

   do => sub {
      my $inbound_server = SyTest::Federation::Server->new;
      $loop->add( $inbound_server );

      provide inbound_server => $inbound_server;

      require IO::Async::SSL;

      $inbound_server->listen(
         host    => "localhost",
         service => "",
         extensions => [qw( SSL )],
         # Synapse currently only talks IPv4
         family => "inet",

         SSL_key_file => "$DIR/server.key",
         SSL_cert_file => "$DIR/server.crt",
      )->on_done( sub {
         my ( $listener ) = @_;
         my $sock = $listener->read_handle;

         my $server_name = sprintf "%s:%d", $sock->sockhostname, $sock->sockport;

         my ( $pkey, $skey ) = Crypt::NaCl::Sodium->sign->keypair;

         my $fedparams = FederationParams( $server_name, "ed25519:1", $pkey, $skey );

         # For now, the federation keystore is just a hash keyed on "origin/keyid"
         my $keystore = {};

         my $outbound_client = SyTest::Federation::Client->new(
            federation_params => $fedparams,
            keystore          => $keystore,
            uri_base          => "/_matrix/federation/v1",
         );
         $loop->add( $outbound_client );

         $listener->configure(
            federation_params => $fedparams,
            keystore          => $keystore,
            client            => $outbound_client,
         );

         provide outbound_client => $outbound_client;
      });
   };

# A small test to check that our own federation server simulation is working
# correctly. If this test fails, it *ALWAYS* indicates a failure of SyTest
# itself and not of the homeserver being tested.
test "Checking local federation server",
   requires => [qw( inbound_server http_client )],

   check => sub {
      my ( $inbound_server, $client ) = @_;

      my $key_id = $inbound_server->key_id;
      my $local_server_name = $inbound_server->server_name;

      $client->do_request(
         method => "GET",
         uri    => "https://$local_server_name/_matrix/key/v2/server/$key_id",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Keyserver response", $body;

         assert_json_keys( $body, qw( server_name valid_until_ts verify_keys signatures tls_fingerprints ));

         assert_json_string( $body->{server_name} );
         $body->{server_name} eq $local_server_name or
            die "Expected server_name to be $local_server_name";

         assert_json_number( $body->{valid_until_ts} );
         $body->{valid_until_ts} / 1000 > time or
            die "Key valid_until_ts is in the past";

         keys %{ $body->{verify_keys} } or
            die "Expected some verify_keys";

         exists $body->{verify_keys}{$key_id} or
            die "Expected to find the '$key_id' key in verify_keys";

         assert_json_keys( my $key = $body->{verify_keys}{$key_id}, qw( key ));

         assert_base64_unpadded( $key->{key} );

         keys %{ $body->{signatures} } or
            die "Expected some signatures";

         $body->{signatures}{$local_server_name} or
            die "Expected a signature from $local_server_name";

         my $signature = $body->{signatures}{$local_server_name}{$key_id} or
            die "Expected a signature from $local_server_name using $key_id";

         assert_base64_unpadded( $signature );

         # TODO: verify it?

         assert_json_list( $body->{tls_fingerprints} );
         @{ $body->{tls_fingerprints} } > 0 or
            die "Expected some tls_fingerprints";

         foreach ( @{ $body->{tls_fingerprints} } ) {
            assert_json_object( $_ );

            # TODO: Check it has keys named by the algorithms
         }

         Future->done(1);
      });
   };
