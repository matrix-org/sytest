use File::Basename qw( dirname );
use Net::Async::HTTP::Server 0.09;  # request_class with bugfix
use IO::Async::SSL;

use SyTest::HTTPClient;
use SyTest::HTTPServer::Request;

my $DIR = dirname( __FILE__ );

struct Awaiter => [qw( pathmatch filter future )];

prepare "Environment closures for receiving HTTP pokes",
   requires => [qw( )],

   provides => [qw( test_http_server_uri_base )],

   do => sub {
      my $listen_host = "localhost";

      my $http_server = SyTest::HTTPServer->new;
      $loop->add( $http_server );

      push our @EXPORT, qw( await_http_request );

      my $http_client;

      $http_server->listen(
         addr => {
            family   => "inet",
            socktype => "stream",
            port     => 0,
         },
         extensions => ["SSL"],
         SSL_cert_file => "$DIR/../keys/tls-selfsigned.crt",
         SSL_key_file => "$DIR/../keys/tls-selfsigned.key",
      )->then( sub {
         my ( $listener ) = @_;
         my $sockport = $listener->read_handle->sockport;

         my $uri_base = "https://$listen_host:$sockport";

         provide test_http_server_uri_base => $uri_base;

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
   };

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

      if( $CLIENT_LOG ) {
         my $green = -t STDOUT ? "\e[1;32m" : "";
         my $reset = -t STDOUT ? "\e[m" : "";
         print "${green}Received Request${reset} for $method $path:\n";
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
