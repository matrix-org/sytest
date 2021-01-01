use Cwd qw( abs_path );
use File::Basename qw( dirname );
use File::Path qw( make_path );
use Net::Async::HTTP::Server 0.09;  # request_class with bugfix
use IO::Async::SSL;

use SyTest::HTTPClient;
use SyTest::HTTPServer::Request;
use SyTest::SSL qw( ensure_ssl_key create_ssl_cert );

my $DIR = dirname( __FILE__ );

struct Awaiter => [qw( pathmatch filter future )];

push our @EXPORT, qw(
   ServerInfo await_http_request TEST_SERVER_INFO
   start_test_server_ssl
);

struct ServerInfo => [qw( server_name client_location federation_host federation_port )];

=head2 start_test_server_ssl

   my $listener = start_test_server_ssl( $server ) -> get;

Creates a TLS cert signed by the CA, and configures an IO::Async::Listener to start listening with it.

=cut

sub start_test_server_ssl {
   my ( $server ) = @_;

   my $test_server_dir = abs_path( $main::WORK_DIR."/test-server" );
   -d $test_server_dir or make_path( $test_server_dir );

   my $ssl_cert = "$test_server_dir/server.crt";
   my $ssl_key = "$test_server_dir/server.key";
   ensure_ssl_key( $ssl_key );
   create_ssl_cert( $ssl_cert, $ssl_key, $BIND_HOST );

   return $server->listen(
      host          => $BIND_HOST,
      service       => 0,
      extensions    => [qw( SSL )],
      SSL_key_file  => $ssl_key,
      SSL_cert_file => $ssl_cert,
   );
}

our $TEST_SERVER_INFO = fixture(
   requires => [],

   setup => sub {
      my $listen_host = $BIND_HOST;

      my $http_server = SyTest::HTTPServer->new;
      $loop->add( $http_server );

      my $http_client;
      my $server_info;

      start_test_server_ssl( $http_server )->then( sub {
         my ( $listener ) = @_;
         my $sockport = $listener->read_handle->sockport;

         $OUTPUT->diag( "Started test HTTPS Server at $listen_host:$sockport" );

         my $uri_base = "https://$listen_host:$sockport";

         $server_info = ServerInfo( "$listen_host:$sockport", $uri_base,
                                    $listen_host, $sockport );

         $http_client = SyTest::HTTPClient->new(
            uri_base => $uri_base,
         );
         $loop->add( $http_client );

         Future->needs_all(
            Future->wait_any(
               await_http_request( "/http_server_self_test", sub {1} ),

               delay( 10 )
                  ->then_fail( "Timed out waiting for request" ),
            )->then( sub {
               my ( $request ) = @_;

               $request->body_from_json->{some_key} eq "some_value" or
                  die "Expected JSON with {\"some_key\":\"some_value\"}";

               $request->respond_json( {} );
               Future->done();
            }),

            $http_client->do_request_json(
               method  => "POST",
               uri     => "/http_server_self_test",
               content => {
                  some_key => "some_value",
               },
            )->then_done(1),
         )
      })->then( sub {
         Future->needs_all(
            Future->wait_any(
               await_http_request( "/http_server_self_test", sub {1} ),

               delay( 10 )
                  ->then_fail( "Timed out waiting for request" ),
            )->then( sub {
               my ( $request ) = @_;

               $request->respond_json( {
                  response_key => "response_value",
               } );
               Future->done();
            }),

            $http_client->do_request_json(
               method => "POST",
               uri     => "/http_server_self_test",
               content => {},
            )->then( sub {
               my ( $response_body ) = @_;

               $response_body->{response_key} eq "response_value" or
                  die "Expected JSON with {\"response_key\":\"response_value\"}";

               Future->done(1);
            }),
         )
      })
      ->then( sub {
         Future->done( $server_info );
      });
   },
);

# List of Awaiter structs
my @pending_awaiters;

package SyTest::HTTPServer {
   use base qw( Net::Async::HTTP::Server );

   use List::UtilsBy 0.10 qw( extract_first_by );
   use URI::Escape qw( uri_unescape );

   sub _init
   {
      my $self = shift;
      my ( $params ) = @_;

      $params->{request_class} ||= "SyTest::HTTPServer::Request";
      $self->SUPER::_init( $params );
   }

   sub on_request
   {
      my ( $self, $request ) = @_;

      my $method = $request->method;
      my $path = uri_unescape $request->path;
      my $qs = $request->query_string;
      if ( defined $qs ) {
         $qs = "?" . $qs;
      }
      else {
         $qs = "";
      }

      if( $CLIENT_LOG ) {
         my $green = -t STDOUT ? "\e[1;32m" : "";
         my $reset = -t STDOUT ? "\e[m" : "";
         print "${green}Received Request${reset} for $method ${path}${qs}:\n";
         #TODO log the HTTP Request headers
         print "  $_\n" for split m/\n/, $request->body;
         print "-- \n";
      }

      my $awaiter = extract_first_by {
         my $pathmatch = $_->pathmatch;
         return 0 unless ( !ref $pathmatch and $path eq $pathmatch ) or
                         ( ref $pathmatch  and $path =~ $pathmatch );

         return 0 if $_->filter and not $_->filter->( $request );

         return 1;
      } @pending_awaiters;

      if( $awaiter ) {
         $awaiter->future->done( $request );
         return;
      }
      else {
         warn "Received spurious HTTP request to $path\n";
      }
   }
}

sub await_http_request
{
   my ( $pathmatch, $filter, %args ) = @_;
   my $failmsg = SyTest::CarpByFile::shortmess(
      "Timed out waiting for an HTTP request matching $pathmatch"
   );

   my $f = $loop->new_future;

   push @pending_awaiters, Awaiter( $pathmatch, $filter, $f );

   my $timeout = $args{timeout} // 10;

   return $f if !$timeout;

   return Future->wait_any(
      $f,

      delay( $timeout )
         ->then_fail( $failmsg ),
   );
};
