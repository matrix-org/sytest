package SyTest::HTTPClient;

use strict;
use warnings;

# A subclass of NaHTTP that stores a URI base, and has convenient JSON
# encoding/decoding wrapper methods

use base qw( Net::Async::HTTP );
Net::Async::HTTP->VERSION( '0.36' ); # PUT content bugfix

use JSON qw( encode_json decode_json );

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( uri_base )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   $self->SUPER::configure( %params );
}

sub do_request
{
   my $self = shift;
   my %params = @_;

   my $uri = URI->new( $self->{uri_base} . $params{uri} );
   $uri->query_form( %{ $params{params} } ) if $params{params};

   # Also set verify_mode = 0 to not complain about self-signed SSL certs
   $params{SSL_verify_mode} = 0;

   $self->SUPER::do_request(
      %params,
      uri => $uri,
   );
}

sub do_request_json
{
   my $self = shift;
   my %params = @_;

   if( defined( my $content = $params{content} ) ) {
      $params{content} = encode_json $content;
      $params{content_type} //= "text/json";
   }

   $self->do_request( %params )->then( sub {
      my ( $response ) = @_;

      unless( $response->code == 200 ) {
         my $message = $response->message;
         $message =~ s/\r?\n?$//; # because HTTP::Response doesn't do this

         return Future->fail( "HTTP Request failed (${\$response->code} $message)",
            http => $response, $response->request );
      }

      my $content = decode_json $response->content;
      Future->done( $content, $response );
   });
}

1;
