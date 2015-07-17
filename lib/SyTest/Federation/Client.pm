package SyTest::Federation::Client;

use strict;
use warnings;

use base qw( SyTest::Federation::_Base SyTest::HTTPClient );

use MIME::Base64 qw( decode_base64 );
use HTTP::Headers::Util qw( join_header_words );

sub _fetch_key
{
   my $self = shift;
   my ( $server_name, $key_id ) = @_;

   $self->do_request_json(
      method   => "GET",
      full_uri => "https://$server_name/_matrix/key/v2/server/$key_id",
   )->then( sub {
      my ( $body ) = @_;

      defined $body->{server_name} and $body->{server_name} eq $server_name or
         return Future->fail( "Response 'server_name' does not match", matrix => );

      $body->{verify_keys} and $body->{verify_keys}{$key_id} and my $key = $body->{verify_keys}{$key_id}{key} or
         return Future->fail( "Response did not provide key '$key_id'", matrix => );

      $key = decode_base64( $key );

      # TODO: Check the self-signedness of the key response

      Future->done( $key );
   });
}

sub do_request_json
{
   my $self = shift;
   my %params = @_;

   my $uri = $self->full_uri_for( %params );

   my $fedparams = $self->{federation_params};

   my $origin = $fedparams->server_name;
   my $key_id = $fedparams->key_id;

   my %signing_block = (
      method => $params{method},
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

1;
