package SyTest::HTTPClient;

use strict;
use warnings;

# A subclass of NaHTTP that stores a URI base, and has convenient JSON
# encoding/decoding wrapper methods

use base qw( Net::Async::HTTP );
Net::Async::HTTP->VERSION( '0.36' ); # PUT content bugfix

use JSON qw( encode_json decode_json );

use constant MIME_TYPE_JSON => "application/json";

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( uri_base )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   $self->SUPER::configure( %params );
}

sub full_uri_for
{
   my $self = shift;
   my %params = @_;

   my $uri;
   if( defined $self->{uri_base} ) {
      $uri = URI->new( $self->{uri_base} );
      if( defined $params{full_uri} ) {
         $uri->path( $params{full_uri} );
      }
      else {
         $uri->path( $uri->path . $params{uri} ); # In case of '#room' fragments
      }
   }
   else {
      $uri = URI->new( $params{uri} );
   }
   $uri->query_form( %{ $params{params} } ) if $params{params};

   return $uri;
}

sub do_request
{
   my $self = shift;
   my %params = @_;

   my $uri = $self->full_uri_for( %params );

   # Also set verify_mode = 0 to not complain about self-signed SSL certs
   $params{SSL_verify_mode} = 0;

   $self->SUPER::do_request(
      %params,
      uri => $uri,
   )->then( sub {
      my ( $response ) = @_;

      unless( $response->code == 200 ) {
         my $message = $response->message;
         $message =~ s/\r?\n?$//; # because HTTP::Response doesn't do this

         return Future->fail( "HTTP Request failed (${\$response->code} $message)",
            http => $response, $response->request );
      }

      my $content = $response->content;

      if( $response->header( "Content-type" ) eq MIME_TYPE_JSON ) {
         $content = decode_json $content;
      }

      Future->done( $content, $response );
   })->else_with_f( sub {
      my ( $f, $message, $name, @args ) = @_;
      return $f unless defined $name and
                       $name eq "http" and
                       my $response = $args[0];
      return $f unless $response->content_type eq MIME_TYPE_JSON;

      # Most HTTP failures from synapse contain more detailed information in a
      # JSON-encoded response body.
      return Future->fail( "$message\n" . $response->decoded_content, $name => @args );
   });
}

sub do_request_json
{
   my $self = shift;
   my %params = @_;

   if( defined( my $content = $params{content} ) ) {
      $params{content} = encode_json $content;
      $params{content_type} //= MIME_TYPE_JSON;
   }

   $self->do_request( %params );
}

1;
