use File::Basename qw( dirname );

use IO::Socket::IP 0.04; # ->sockhostname
Net::Async::HTTP->VERSION( '0.39' ); # ->GET with 'headers'

require IO::Async::SSL;

use Crypt::NaCl::Sodium;

use SyTest::Federation::Datastore;
use SyTest::Federation::Client;
use SyTest::Federation::Server;

push our @EXPORT, qw( INBOUND_SERVER OUTBOUND_CLIENT create_federation_server );

sub create_federation_server
{
   my $server = SyTest::Federation::Server->new;
   $loop->add( $server );

   start_test_server_ssl( $server )->on_done( sub {
      my ( $server ) = @_;
      my $sock = $server->read_handle;

      my $server_name = sprintf "%s:%d", $sock->sockhostname, $sock->sockport;

      my ( $pkey, $skey ) = Crypt::NaCl::Sodium->sign->keypair;

      my $datastore = SyTest::Federation::Datastore->new(
         server_name => $server_name,
         key_id      => "ed25519:1",
         public_key  => $pkey,
         secret_key  => $skey,
      );

      my $outbound_client = SyTest::Federation::Client->new(
         datastore => $datastore,
         uri_base  => "/_matrix/federation",
        );
      $loop->add( $outbound_client );

      $server->configure(
         datastore => $datastore,
         client    => $outbound_client,
        );

      Future->done($server)
   });
}

our $INBOUND_SERVER = fixture(
   setup => sub {
      create_federation_server();
   }
);

our $OUTBOUND_CLIENT = fixture(
   requires => [ $INBOUND_SERVER ],

   setup => sub {
      my ( $inbound_server ) = @_;

      Future->done( $inbound_server->client );
   },
);

# A small test to check that our own federation server simulation is working
# correctly. If this test fails, it *ALWAYS* indicates a failure of SyTest
# itself and not of the homeserver being tested.
test "Checking local federation server",
   requires => [ $INBOUND_SERVER, $main::HTTP_CLIENT ],

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

push @EXPORT, qw( federation_user_id_fixture );

my $next_user_id = 0;

=head2 federation_user_id_fixture

   $fixture = federation_user_id_fixture

Returns a new Fixture, which when provisioned will allocate a new user ID
within the "fake" internal federation context, and return it as a string.

=cut

sub federation_user_id_fixture
{
   fixture(
      requires => [ $INBOUND_SERVER ],

      setup => sub {
         my ( $inbound_server ) = @_;

         my $user_id = sprintf "\@__ANON__-%d:%s", $next_user_id++, $inbound_server->server_name;
         Future->done( $user_id );
      },
   );
}
