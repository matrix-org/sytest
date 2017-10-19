use IO::Async::SSL;
use IO::Async::Listener 0.69;  # for ->configure( handle => undef )
use SyTest::Identity::Server;
use File::Basename qw( dirname );

my $DIR = dirname( __FILE__ );

push our @EXPORT, qw( id_server_fixture );

sub id_server_fixture
{
   return fixture(
      name => 'id_server_fixture',

      setup => sub {
         my $id_server = SyTest::Identity::Server->new;
         $loop->add( $id_server );

         $id_server->listen(
            host          => $BIND_HOST,
            service       => "",
            extensions    => [qw( SSL )],
            # Synapse currently only talks IPv4
            family        => "inet",

            SSL_cert_file => "$DIR/../keys/tls-selfsigned.crt",
            SSL_key_file  => "$DIR/../keys/tls-selfsigned.key",
         )->then_done( $id_server );
      },

      teardown => sub {
         my ( $id_server ) = @_;
         $loop->remove( $id_server );

         Future->done;
      },
   );
}
