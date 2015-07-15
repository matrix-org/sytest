use File::Basename qw( dirname );

use IO::Socket::IP 0.04; # ->sockhostname
Net::Async::HTTP->VERSION( '0.39' ); # ->GET with 'headers'

use Crypt::NaCl::Sodium;

my $DIR = dirname( __FILE__ );

struct FederationParams => [qw( server_name key_id public_key secret_key )];

prepare "Creating inbound federation HTTP server and outbound federation client",
   requires => [qw( first_home_server )],

   provides => [qw( local_server_name inbound_server outbound_client )],

   do => sub {
      my ( $first_home_server ) = @_;

      my $inbound_server = SyTest::Federation::Server->new;
      $loop->add( $inbound_server );

      provide inbound_server => $inbound_server;

      require IO::Async::SSL;

      $inbound_server->listen(
         host    => "localhost",
         service => "",
         extensions => [qw( SSL )],

         SSL_key_file => "$DIR/server.key",
         SSL_cert_file => "$DIR/server.crt",
      )->on_done( sub {
         my ( $listener ) = @_;
         my $sock = $listener->read_handle;

         my $server_name = sprintf "%s:%d", $sock->sockhostname, $sock->sockport;

         provide local_server_name => $server_name;

         my ( $pkey, $skey ) = Crypt::NaCl::Sodium->sign->keypair;

         my $fedparams = FederationParams( $server_name, "ed25519:1", $pkey, $skey );

         $listener->configure(
            federation_params => $fedparams,
         );

         my $outbound_client = SyTest::Federation::Client->new(
            federation_params => $fedparams,
            uri_base          => "https://$first_home_server/_matrix/federation/v1",
         );
         $loop->add( $outbound_client );

         provide outbound_client => $outbound_client;
      });
   };

# A small test to check that our own federation server simulation is working
# correctly. If this test fails, it *ALWAYS* indicates a failure of SyTest
# itself and not of the homeserver being tested.
test "Checking local federation server",
   requires => [qw( local_server_name inbound_server http_client )],

   check => sub {
      my ( $local_server_name, $inbound_server, $client ) = @_;

      my $key_id = $inbound_server->key_id;

      $client->do_request(
         method => "GET",
         uri    => "https://$local_server_name/_matrix/key/v2/server/$key_id",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Keyserver response", $body;

         require_json_keys( $body, qw( server_name valid_until_ts verify_keys signatures tls_fingerprints ));

         require_json_string( $body->{server_name} );
         $body->{server_name} eq $local_server_name or
            die "Expected server_name to be $local_server_name";

         require_json_number( $body->{valid_until_ts} );
         $body->{valid_until_ts} / 1000 > time or
            die "Key valid_until_ts is in the past";

         keys %{ $body->{verify_keys} } or
            die "Expected some verify_keys";

         exists $body->{verify_keys}{$key_id} or
            die "Expected to find the '$key_id' key in verify_keys";

         require_json_keys( my $key = $body->{verify_keys}{$key_id}, qw( key ));

         require_base64_unpadded( $key->{key} );

         keys %{ $body->{signatures} } or
            die "Expected some signatures";

         $body->{signatures}{$local_server_name} or
            die "Expected a signature from $local_server_name";

         my $signature = $body->{signatures}{$local_server_name}{$key_id} or
            die "Expected a signature from $local_server_name using $key_id";

         require_base64_unpadded( $signature );

         # TODO: verify it?

         require_json_list( $body->{tls_fingerprints} );
         @{ $body->{tls_fingerprints} } > 0 or
            die "Expected some tls_fingerprints";

         foreach ( @{ $body->{tls_fingerprints} } ) {
            require_json_object( $_ );

            # TODO: Check it has keys named by the algorithms
         }

         Future->done(1);
      });
   };

package SyTest::Federation::_Base;

use mro 'c3';
use Protocol::Matrix qw( sign_json );

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( federation_params )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   $self->next::method( %params );
}

sub server_name
{
   my $self = shift;
   return $self->{federation_params}->server_name;
}

sub key_id
{
   my $self = shift;
   return $self->{federation_params}->key_id;
}

sub sign_data
{
   my $self = shift;
   my ( $data ) = @_;

   my $fedparams = $self->{federation_params};

   sign_json( $data,
      secret_key => $fedparams->secret_key,
      origin     => $fedparams->server_name,
      key_id     => $fedparams->key_id,
   );
}

package SyTest::Federation::Client;
use base qw( SyTest::Federation::_Base SyTest::HTTPClient );

use HTTP::Headers::Util qw( join_header_words );

sub do_request_json
{
   my $self = shift;
   my %params = @_;

   my $uri = $self->full_uri_for( %params );

   my $fedparams = $self->{federation_params};

   my $origin = $fedparams->server_name;
   my $key_id = $fedparams->key_id;

   my %signing_block = (
      method => "GET",
      uri    => $uri->path_query,  ## TODO: Matrix spec is unclear on this bit
      origin => $origin,
      destination => $uri->authority,
   );

   if( defined $params{content} ) {
      $signing_block{content} = $params{content};
   }

   $self->sign_data( \%signing_block );

   my $signature = $signing_block{signatures}{$origin}{$key_id};

   my $auth = "X-Matrix " . join_header_words(
      [ origin => $origin ],
      [ key    => $key_id ],
      [ sig    => $signature ],
   );

   # TODO: SYN-437 synapse does not like OWS between auth-param elements
   $auth =~ s/, +/,/g;

   $self->SUPER::do_request_json(
      %params,
      headers => [
         @{ $params{headers} || [] },
         Authorization => $auth,
      ],
   );
}

package SyTest::Federation::Server;
use base qw( SyTest::Federation::_Base Net::Async::HTTP::Server );

no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use feature qw( switch );

use Carp;

use Protocol::Matrix qw( encode_base64_unpadded );
use HTTP::Headers::Util qw( split_header_words );
use JSON qw( encode_json );

sub make_request
{
   my $self = shift;
   return SyTest::HTTPServer::Request->new( @_ );
}

sub on_request
{
   my $self = shift;
   my ( $req ) = @_;

   ::log_if_fail "Incoming federation request", $req;

   my $path = $req->path;
   unless( $path =~ s{^/_matrix/}{} ) {
      $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
      return;
   }

   my @pc = split m{/}, $path;

   # 'key' requests don't need to be signed
   unless( $pc[0] eq "key" ) {
      if( !eval { $self->_check_authorization( $req ); 1 } ) {
         chomp( my $message = $@ );
         my $body = encode_json {
            errcode => "M_UNAUTHORIZED",
            error   => $message,
         };

         $req->respond( HTTP::Response->new(
            403, undef, [
               Content_Length => length $body,
               Content_Type   => "application/json",
            ], $body
         ) );
         return;
      }
   }

   my @trial;
   while( @pc ) {
      push @trial, shift @pc;
      if( my $code = $self->can( "on_request_" . join "_", @trial ) ) {
         $self->adopt_future(
            $code->( $self, $req, @pc )->on_done( sub {
               for ( shift ) {
                  when( "json" ) {
                     my ( $resp ) = @_;
                     $self->sign_data( $resp );
                     $req->respond_json( $resp );
                  }
                  default {
                     croak "Unsure how to handle response type $_";
                  }
               }
            })
         );
         return;
      }
   }

   print STDERR "TODO: Respond to request to /_matrix/${\join '/', @trial}\n";

   $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
}

sub _check_authorization
{
   my $self = shift;
   my ( $req ) = @_;

   my $auth = $req->header( "Authorization" ) // "";

   $auth =~ s/^X-Matrix\s+// or
      die "No Authorization of scheme X-Matrix\n";

   # split_header_words gives us a list of two-element ARRAYrefs
   my %auth_params = map { @$_ } split_header_words( $auth );

   defined $auth_params{$_} or
      die "Missing '$_' parameter to X-Matrix Authorization\n" for qw( origin key sig );

   my $origin = $auth_params{origin};

   my %to_sign = (
      method      => $req->method,
      uri         => $req->as_http_request->uri->path_query,
      origin      => $origin,
      destination => $self->server_name,
      signatures  => {
         $origin => {
            $auth_params{key} => $auth_params{sig},
         },
      },
   );

   if( length $req->body ) {
      my $body = $req->body_json;

      $origin eq $body->{origin} or
         die "'origin' in Authorization header does not match content";

      $to_sign{content} = $body;
   }

   # TODO: verify signature of %to_sign

   return;
}

sub on_request_key_v2_server
{
   my $self = shift;
   my ( $req, $keyid ) = @_;

   my $sock = $req->stream->read_handle;
   my $ssl = $sock->_get_ssl_object;  # gut-wrench into IO::Socket::SSL - see RT105733
   my $cert = Net::SSLeay::get_certificate( $ssl );

   my $algo = "sha256";
   my $fingerprint = Net::SSLeay::X509_digest( $cert, Net::SSLeay::EVP_get_digestbyname( $algo ) );

   my $fedparams = $self->{federation_params};

   Future->done( json => {
      server_name => $fedparams->server_name,
      tls_fingerprints => [
         { $algo => encode_base64_unpadded( $fingerprint ) },
      ],
      valid_until_ts => ( time + 86400 ) * 1000, # +24h in msec
      verify_keys => {
         $fedparams->key_id => {
            key => encode_base64_unpadded( $fedparams->public_key ),
         },
      },
      old_verify_keys => {},
   } );
}
