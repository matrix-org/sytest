package SyTest::HTTPClient;

use strict;
use warnings;

# A subclass of NaHTTP that stores a URI base, and has convenient JSON
# encoding/decoding wrapper methods

use base qw( Net::Async::HTTP );

use JSON qw( decode_json );

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

   $params{uri} = URI->new( $self->{uri_base} . $params{uri} );

   # Also set verify_mode = 0 to not complain about self-signed SSL certs
   $params{SSL_verify_mode} = 0;

   $self->SUPER::do_request( %params );
}

sub do_request_json
{
   my $self = shift;
   $self->do_request( @_ )->then( sub {
      my ( $response ) = @_;

      my $content = decode_json $response->content;
      Future->done( $content, $response );
   });
}

1;
