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

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   $self->rotate_keys;

   $self->{bindings} = {};
   $self->{expected_tokens} = {};

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
      my $user_agent = $req->header( "User-Agent" );
      if( defined $self->{isvalid_needs_useragent} and $user_agent !~ m/\Q$self->{isvalid_needs_useragent}/ ) {
         die "Wrong useragent made /isvalid request";
      }
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
      my $mxid = $self->{bindings}{$address};
      if ( "email" eq $medium and defined $mxid ) {
         $resp{medium} = $medium;
         $resp{address} = $address;
         $resp{mxid} = $mxid;

         my $sock = $self->read_handle;
         my $name = sprintf "%s:%d", $sock->sockhostname, $sock->sockport;
         sign_json( \%resp,
            secret_key => $self->{private_key},
            origin => $name,
            key_id => "ed25519:0",
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
      my $token = $self->{expected_tokens}{ join "\0", $medium, $address, $sender, $room_id };
      unless( defined $token ) {
         $req->respond( HTTP::Response->new( 500, "Internal Server Error", [ Content_Length => 0 ] ) );
         return;
      }
      $resp{token} = $token;
      $resp{public_key} = $self->{keys}{"ed25519:0"};
      $req->respond_json( \%resp );
   }
   else {
      $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
   }
}

sub stub_token {
   my $self = shift;
   my ( $token, $medium, $invitee_email, $inviter_mxid, $room_id ) = @_;

   $self->{expected_tokens}{ join "\0", $medium, $invitee_email, $inviter_mxid, $room_id } = $token;
}

1;
