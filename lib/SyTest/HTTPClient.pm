package SyTest::HTTPClient;

use strict;
use warnings;

# A subclass of NaHTTP that stores a URI base, and has convenient JSON
# encoding/decoding wrapper methods

use base qw( Net::Async::HTTP );
Net::Async::HTTP->VERSION( '0.36' ); # PUT content bugfix

use JSON;
my $json = JSON->new->convert_blessed;

use Future 0.33; # ->catch
use Net::SSLeay 1.59; # TLSv1.2

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

   $params{SSL_cipher_list} = "HIGH";

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
         $content = wrap_numbers( $json->decode( $content ) );
      }

      Future->done( $content, $response );
   })->catch_with_f( http => sub {
      my ( $f, $message, $name, @args ) = @_;
      return $f unless my $response = $args[0];
      return $f unless $response->content_type eq MIME_TYPE_JSON;

      # Most HTTP failures from synapse contain more detailed information in a
      # JSON-encoded response body.

      # Full URI is going to be long and messy because of query params; trim them
      my $uri_without_query = join "", $uri->scheme, "://", $uri->authority, $uri->path, "?...";

      return Future->fail( "$message from $params{method} $uri_without_query\n" . $response->decoded_content, $name => @args );
   });
}

sub do_request_json
{
   my $self = shift;
   my %params = @_;

   if( defined( my $content = $params{content} ) ) {
      $params{content} = $json->encode( $content );
      $params{content_type} //= MIME_TYPE_JSON;
   }

   $self->do_request( %params );
}

## TERRIBLY RUDE but it seems to work
package JSON::number {
   use overload '0+' => sub { ${ $_[0] } },
                fallback => 1;
   sub new {
      my ( $class, $value ) = @_;
      return bless \$value, $class;
   }

   sub TO_JSON { 0 + ${ $_[0] } }

   Data::Dump::Filtered::add_dump_filter( sub {
      ( ref($_[1]) // '' ) eq __PACKAGE__
         ? { dump => "JSON::number(${ $_[1] })" }
         : undef;
   });
}

# A terrible internals hack that relies on the dualvar nature of the ^ operator
sub SvPOK { ( $_[0] ^ $_[0] ) =~ m/\0/ }

sub wrap_numbers
{
   my ( $d ) = @_;
   if( defined $d and !ref $d and !SvPOK $d ) {
      return JSON::number->new( $d );
   }
   elsif( ref $d eq "ARRAY" ) {
      return [ map wrap_numbers($_), @$d ];
   }
   elsif( ref $d eq "HASH" ) {
      return { map { $_, wrap_numbers( $d->{$_} ) } keys %$d };
   }
   else {
      return $d;
   }
}

1;
