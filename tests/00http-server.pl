use Net::Async::HTTP::Server;
use JSON qw( decode_json );

multi_test "Environment closures for receiving HTTP pokes",
   requires => [qw( internal_server_port )],

   provides => [qw( test_http_server_uri_base await_http_request )],

   do => sub {
      my ( $listen_port ) = @_;

      my $listen_host = "localhost";

      # Hashes from paths to arrays of pending requests and futures.
      my $pending_requests = {};
      my $pending_futures = {};

      my $handle_request = sub {
         my ( $request, $f ) = @_;
         my $content = $request->body;
         if( $request->header( "Content-Type" ) eq "application/json" ) {
            $content = decode_json $content;
         }
         $f->done( $content, $request );
      };

      my $http_server = Net::Async::HTTP::Server->new(
         on_request => sub {
            my ( $self, $request ) = @_;

            # TODO: This should be a parameter of NaH:Server
            bless $request, "SyTest::HTTPServer::Request" if ref( $request ) eq "Net::Async::HTTP::Server::Request";

            my $method = $request->method;
            my $path = $request->path;

            if( $CLIENT_LOG ) {
               print STDERR "\e[1;32mReceived Request\e[m for $method $path:\n";
               #TODO log the HTTP Request headers
               print STDERR "  $_\n" for split m/\n/, $request->body;
               print STDERR "-- \n";
            }

            if( my $pending_future = shift @{ $pending_futures->{$path} } ) {
               $handle_request->( $request, $pending_future );
            }
            else {
               push @{ $pending_requests->{$path} }, $request;
            }
         }
      );
      $loop->add( $http_server );

      my $uri_base = "http://$listen_host:$listen_port";

      provide test_http_server_uri_base => $uri_base;

      my $await_http_request;
      $await_http_request = sub {
         my ( $path, $matches ) = @_;

         my $f = $loop->new_future;
         my $pending_request = shift @{ $pending_requests->{$path} };

         if( defined $pending_request ) {
            $handle_request->( $pending_request, $f );
         }
         else {
            push @{ $pending_futures->{$path} }, $f;
         }

         return $f->then( sub {
            my ( $body, $request ) = @_;
            if( $matches->( $body, $request ) ) {
               return Future->done( $body, $request );
            } else {
               return $await_http_request->( $path, $matches );
            }
         });
      };

      provide await_http_request => $await_http_request;

      my $http_client = SyTest::HTTPClient->new(
         uri_base => $uri_base,
      );
      $loop->add( $http_client );

      $http_server->listen(
         addr => {
            family   => "inet",
            socktype => "stream",
            port     => $listen_port
         },
      )->then( sub {
         pass "Listening on $uri_base";

         Future->needs_all(
            Future->wait_any(
               $await_http_request->( "/http_server_self_test", sub {1} ),

               delay( 10 )
                  ->then_fail( "Timed out waiting for request" ),
            )->then( sub {
               my ( $request_body, $request ) = @_;

               $request_body->{some_key} eq "some_value" or
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
               $await_http_request->( "/http_server_self_test", sub {1} ),

               delay( 10 )
                  ->then_fail( "Timed out waiting for request" ),
            )->then( sub {
               my ( $request_body, $request ) = @_;

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
      })->on_done( sub {
         pass "HTTP server self-checks pass";
      })
   };

# A somewhat-hackish way to give NaH:Server::Request objects a ->respond_json method
package SyTest::HTTPServer::Request;
use base qw( Net::Async::HTTP::Server::Request );

use JSON qw( encode_json );

sub respond_json
{
   my $self = shift;
   my ( $json ) = @_;

   my $response = HTTP::Response->new( 200 );
   $response->add_content( encode_json $json );
   $response->content_type( "application/json" );
   $response->content_length( length $response->content );

   $self->respond( $response );
}
