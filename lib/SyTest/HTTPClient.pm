package SyTest::HTTPClient;

use strict;
use warnings;

# A subclass of NaHTTP that stores a URI base, and has convenient JSON
# encoding/decoding wrapper methods

use Carp;

use base qw( Net::Async::HTTP );
Net::Async::HTTP->VERSION( '0.36' ); # PUT content bugfix

use JSON;
my $json = JSON->new->convert_blessed(1)->utf8(1);

use Future 0.33; # ->catch
use List::Util qw( any );
use Net::SSLeay 1.59; # TLSv1.2
use Scalar::Util qw( blessed reftype );

use SyTest::JSONSensible;

use constant MIME_TYPE_JSON => "application/json";

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   # Turn off pipelining because it gets in the way of longpolls
   $params->{pipeline} = 0;

   $self->SUPER::_init( $params );
}

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( uri_base restrict_methods server_name )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   $self->SUPER::configure( %params );
}

sub server_name
{
   my $self = shift;
   return $self->{server_name};
}

sub full_uri_for
{
   my $self = shift;
   my %params = @_;

   my $uri;
   if( defined $self->{uri_base} ) {
      $uri = URI->new( $self->{uri_base} );
      if( !defined $params{full_uri} ) {
         $uri->path( $uri->path . $params{uri} ); # In case of '#room' fragments
      }
      elsif( $params{full_uri} =~ m/^http/ ) {
         $uri = URI->new( $params{full_uri} );
      }
      else {
         $uri->path( $params{full_uri} );
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

   croak "must give a method" unless $params{method};

   my $uri = $self->full_uri_for( %params );

   # Also set verify_mode = 0 to not complain about self-signed SSL certs
   $params{SSL_verify_mode} = 0;

   $params{SSL_cipher_list} = "HIGH";

   if( $self->{restrict_methods} ) {
      any { $params{method} eq $_ } @{ $self->{restrict_methods} } or
         croak "This HTTP client is not allowed to perform $params{method} requests";
   }

   # workaround for https://rt.cpan.org/Public/Bug/Display.html?id=134411
   my $host_header = $uri->host;
   if( ! ( $uri->scheme eq 'https' && $uri->port == 443 ) &&
       ! ( $uri->scheme eq 'http' && $uri->port == 80 )
      ) {
       # nonstandard port: requires better Host header
       $host_header .= ":" . $uri->port;
   };
   my $headers = delete $params{headers} // [];
   if( reftype $headers eq "ARRAY" ) {
      $headers = [
         "Host" => $host_header,
         @$headers,
      ];
   }
   elsif( reftype $headers eq "HASH" ) {
      $headers = {
         "Host" => $host_header,
         %$headers,
      };
   } else {
      croak "headers must be an arrayref or hashref";
   }


   $self->SUPER::do_request(
      %params,
      headers => $headers,
      uri => $uri,
   )->then( sub {
      my ( $response ) = @_;

      unless( $response->code == 200 ) {
         my $message = $response->message;
         $message =~ s/\r?\n?$//; # because HTTP::Response doesn't do this

         return Future->fail( "HTTP Request failed ( ${\$response->code} $message $uri )",
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
      !blessed $content and ( ref $content eq "HASH" or ref $content eq "ARRAY" ) or
         croak "->do_request_json content must be a plain HASH or ARRAY reference";

      $params{content} = $json->encode( $content );
      $params{content_type} //= MIME_TYPE_JSON;
   }

   $self->do_request( %params );
}

# A terrible internals hack that relies on the dualvar nature of the ^ operator.
# Returns true if perl thinks the argument is a string.
sub SvPOK {
   my ( $s ) = @_;
   return utf8::is_utf8( $s ) || ( $s ^ $s ) ne "0";
}

sub wrap_numbers
{
   my ( $d ) = @_;
   if( defined $d and !ref $d and !SvPOK $d ) {
      return JSON::number( $d );
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
