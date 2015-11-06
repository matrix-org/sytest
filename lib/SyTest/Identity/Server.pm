package SyTest::Identity::Server;

use strict;
use warnings;

use base qw( Net::Async::HTTP::Server );

use Crypt::NaCl::Sodium;
use List::Util qw( any );
use Protocol::Matrix qw( encode_base64_unpadded sign_json );
use SyTest::HTTPServer::Request;
use HTTP::Response;

my $crypto_sign = Crypt::NaCl::Sodium->sign;

my $next_token = 0;

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   $self->rotate_keys;

   $self->{http_client} = SyTest::HTTPClient->new;
   $self->add_child( $self->{http_client} );

   $self->{bindings} = {};
   $self->{invites} = {};

   # Use 'on_request' as a configured parameter rather than a subclass method
   # so that the '$CLIENT_LOG' logic in run-tests.pl can properly put
   # debug-printing wrapping logic around it.
   $params->{on_request} = \&on_request;
   $params->{request_class} ||= "SyTest::HTTPServer::Request";

   return $self->SUPER::_init( @_ );
}

sub rotate_keys
{
   my $self = shift;

   ( $self->{public_key}, $self->{private_key} ) = $crypto_sign->keypair;

   $self->{keys} = {
      "ed25519:0" => encode_base64_unpadded( $self->{public_key} ),
   };
}

sub on_request
{
   my $self = shift;
   my ( $req ) = @_;

   my $path = $req->path;
   my %resp;

   if( $path eq "/_matrix/identity/api/v1/pubkey/isvalid" ) {
      my $is_valid = any { $_ eq $req->query_param("public_key") } values %{ $self->{keys} };
      $resp{valid} = $is_valid ? JSON::true : JSON::false;
      $req->respond_json( \%resp );
   }
   elsif( my ( $key_name ) = $path =~ m#^/_matrix/identity/api/v1/pubkey/([^/]*)$# ) {
      if( defined $self->{keys}->{$key_name} ) {
         $resp{public_key} = $self->{keys}{$key_name};
      }
      $req->respond_json( \%resp );
   }
   elsif( $path eq "/_matrix/identity/api/v1/lookup" ) {
      my ( $req ) = @_;
      my $medium = $req->query_param( "medium" );
      my $address = $req->query_param( "address" );
      if ( !defined $medium or !defined $address ) {
         $req->respond( HTTP::Response->new( 400, "Bad Request", [ Content_Length => 0 ] ) );
         return;
      }
      my $mxid = $self->{bindings}{ join "\0", $medium, $address };
      if ( "email" eq $medium and defined $mxid ) {
         $resp{medium} = $medium;
         $resp{address} = $address;
         $resp{mxid} = $mxid;

         sign_json( \%resp,
            secret_key => $self->{private_key},
            origin     => $self->name,
            key_id     => "ed25519:0",
         );
      }
      $req->respond_json( \%resp );
   }
   elsif( $path eq "/_matrix/identity/api/v1/store-invite" ) {
      my $body = $req->body_from_form;
      my $medium = $body->{medium};
      my $address = $body->{address};
      my $sender = $body->{sender};
      my $room_id = $body->{room_id};
      unless( ( defined $body->{medium} and defined $address and defined $sender and defined $room_id ) ) {
         $req->respond( HTTP::Response->new( 400, "Bad Request", [ Content_Length => 0 ] ) );
         return;
      }
      my $token = "".$next_token++;
      my $key = join "\0", $medium, $address;
      push @{ $self->{invites}->{$key} }, {
         address => $address,
         medium  => $medium,
         room_id => $room_id,
         sender  => $sender,
         token   => $token,
      };
      $resp{token} = $token;
      $resp{public_key} = $self->{keys}{"ed25519:0"};
      $req->respond_json( \%resp );
   }
   else {
      $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
   }
}

sub bind_identity
{
   my $self = shift;
   my ( $hs_uribase, $medium, $address, $user, $before_resp ) = @_;

   $self->{bindings}{ join "\0", $medium, $address } = $user->user_id;

   if( !defined $hs_uribase ) {
      return Future->done( 1 );
   }

   my %resp = (
      address => $address,
      medium  => $medium,
      mxid    => $user->user_id,
   );

   my $invites = $self->{invites}->{ join "\0", $medium, $address };
   if( defined $invites ) {
      foreach my $invite ( @$invites ) {
         $invite->{mxid} = $user->user_id;
         $invite->{signed} = {
            mxid  => $user->user_id,
            token => $invite->{token},
         };
         sign_json( $invite->{signed},
            secret_key => $self->{private_key},
            origin     => $self->name,
            key_id     => "ed25519:0",
         );
      }
      $resp{invites} = $invites;
   }

   sign_json( \%resp,
      secret_key => $self->{private_key},
      origin     => $self->name,
      key_id     => "ed25519:0",
   );

   $before_resp->() if defined $before_resp;

   $self->{http_client}->do_request_json(
      uri     => URI->new( "$hs_uribase/_matrix/federation/v1/3pid/onbind" ),
      method  => "POST",
      content => \%resp,
   );
}

sub name
{
   my $self = shift;
   my $sock = $self->read_handle;
   sprintf "%s:%d", $sock->sockhostname, $sock->sockport;
}

1;
