package SyTest::Identity::Server;

use strict;
use warnings;

use base qw( Net::Async::HTTP::Server );

use Crypt::NaCl::Sodium;
use List::Util qw( any );
use Protocol::Matrix qw( encode_base64_unpadded sign_json );
use MIME::Base64 qw ( encode_base64url );
use SyTest::HTTPServer::Request;
use HTTP::Response;
use Digest::SHA qw( sha256 );

my $crypto_sign = Crypt::NaCl::Sodium->sign;

my $next_token = 0;

my $id_access_token = "testing";

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   $self->rotate_keys;

   $self->{http_client} = SyTest::HTTPClient->new;
   $self->add_child( $self->{http_client} );

   $self->{bindings} = {};
   $self->{invites} = {};

   # String for peppering hashed lookup requests
   $self->{lookup_pepper} = "matrixrocks";

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
   ( $self->{ephemeral_public_key}, $self->{ephemeral_private_key} ) = $crypto_sign->keypair;

   $self->{keys} = {
      "ed25519:0" => encode_base64_unpadded( $self->{public_key} ),
      "ed25519:ephemeral" => encode_base64_unpadded( $self->{ephemeral_public_key} ),
   };
}

sub on_request
{
   my $self = shift;
   my ( $req ) = @_;

   my $path = $req->path;
   my %resp;
   my $key_name;

   if(
      $path eq "/_matrix/identity/api/v1/pubkey/isvalid" or
      $path eq "/_matrix/identity/v2/pubkey/isvalid"
   ) {
      is_valid( $self, $req );
   }
   elsif( $key_name = $path =~ m#^/_matrix/identity/api/v1/pubkey/([^/]*)$# ) {
      pubkey( $self, $req, $key_name );
   }
   elsif( $key_name = $path =~ m#^/_matrix/identity/v2/pubkey/([^/]*)$# ) {
      check_v2( $req );
      pubkey( $self, $req, $key_name );
   }
   elsif( $path eq "/_matrix/identity/api/v1/lookup" ) {
      v1_lookup( $self, $req );
   }
   elsif( $path eq "/_matrix/identity/v2/lookup" ) {
      check_v2( $req );
      v2_lookup( $self, $req );
   }
   elsif( $path eq "/_matrix/identity/v2/hash_details" ) {
      check_v2( $req );
      hash_details( $self, $req );
   }
   elsif( $path eq "/_matrix/identity/api/v1/store-invite" ) {
      store_invite( $self, $req );
   }
   elsif( $path eq "/_matrix/identity/v2/store-invite" ) {
      check_v2( $req );
      store_invite( $self, $req );
   }
   elsif( $path eq "/_matrix/identity/api/v1/3pid/getValidated3pid" ) {
      get_validated_3pid( $self, $req );
   }
   elsif( $path eq "/_matrix/identity/v2/3pid/getValidated3pid" ) {
      check_v2( $req );
      get_validated_3pid( $self, $req );
   }
   elsif ( $path eq "/_matrix/identity/api/v1/3pid/bind" ) {
      do_bind( $self, $req );
   }
   elsif ( $path eq "/_matrix/identity/v2/3pid/bind" ) {
      check_v2( $req );
      do_bind( $self, $req );
   }
   elsif (  # v2 /unbind does not require an id_access_token param
      $path eq "/_matrix/identity/v2/3pid/unbind" or
      $path eq "/_matrix/identity/api/v1/3pid/unbind"
   ) {
      unbind( $self, $req );
   }
   else {
      warn "Unexpected request to Identity Service for $path";
      $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
   }
}

sub check_v2
{
   # Check that either an id_access_token query parameter or JSON body key exists in the req
   my ( $req ) = @_;
   my %resp;

   if (
      $req->query_param("id_access_token") and
      $req->query_param("id_access_token") eq $id_access_token
   ) {
      # We found it!
      return
   }

   # Check the JSON body for the token. This isn't required for all endpoints so only try if
   # the request has a body
   my $found = 0;
   eval {
      # We use an eval in case this request doesn't have a JSON body
      my $body = $req->body_from_json;
      if (
         $body->{id_access_token} and
         $body->{id_access_token} eq $id_access_token
      ) {
         # We found it!
         $found = 1;
      }
   };


   # Couldn't find an access token
   if ( !$found ) {
      $resp{error} = "Missing id_access_token parameter";
      $resp{errcode} = "M_MISSING_PARAM";
      $req->respond_json( \%resp, code => 400 );
   }
}

sub is_valid
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   my $valid = any { $_ eq $req->query_param("public_key") } values %{ $self->{keys} };
   $resp{valid} = $valid ? JSON::true : JSON::false;
   $req->respond_json( \%resp );
}

sub validate_identity
{
   my $self = shift;
   my ( $medium, $address, $client_secret ) = @_;

   my $sid = "session_${\ $self->{sid}++ }";

   $self->{validated}{$sid} = {
      medium       => $medium,
      address      => $address,
   };

   return $sid;
}

sub pubkey
{
   my $self = shift;
   my ( $req, $key_name ) = @_;
   my %resp;

   if( defined $self->{keys}->{$key_name} ) {
      $resp{public_key} = $self->{keys}{$key_name};
   }
   $req->respond_json( \%resp );
}

sub v1_lookup
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

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

sub hash_details
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   $resp{lookup_pepper} = $self->{lookup_pepper};
   @resp{algorithms} = [ "none", "sha256" ];
   $req->respond_json( \%resp );
}

sub v2_lookup
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   # Parse request parameters
   my $body = $req->body_from_json;
   my $addresses = $body->{addresses};
   my $pepper = $body->{pepper};
   my $algorithm = $body->{algorithm};
   if ( !$addresses or !$pepper or !$algorithm ) {
      $req->respond( HTTP::Response->new( 400, "Bad Request", [ Content_Length => 0 ] ) );
      return;
   }

   if ( "none" eq $algorithm ) {
      foreach my $address ( @$addresses ) {
         my @address_medium = split ' ', $address;

         # Check the medium and address are in the right format
         if ( scalar( @address_medium ) ne 2 ) {
            $resp{error} = "Address is not two strings separated by a space: ${address}";
            $resp{errcode} = "M_UNKNOWN";

            $req->respond_json( \%resp, code => 400 );
            return;
         }

         # Parse the medium and address from the string
         my $user_address = $address_medium[0];
         my $user_medium = $address_medium[1];

         # Extract the MXID for this address/medium combo from the bindings hash
         # We need to swap around medium and address here as it's stored $medium, $address
         # locally, not $address, $medium
         my $mxid = $self->{bindings}{ join "\0", $user_medium, $user_address };

         $resp{mappings}{$address} = $mxid;
      }

      # Return the mappings
      $req->respond_json( \%resp );
   }
   elsif ( "sha256" eq $algorithm ) {
      # Check that the user provided the correct pepper
      if ( $self->{lookup_pepper} ne $pepper ) {
         # Return an error message
         $resp{error} = "Incorrect value for lookup_pepper";
         $resp{errcode} = "M_INVALID_PEPPER";
         $resp{algorithm} = "sha256";
         $resp{lookup_pepper} = $self->{lookup_pepper};

         $req->respond_json( \%resp, code => 400 );
         return;
      }

      # Attempt to find the hash of each entry and return the corresponding mxid
      foreach my $hash ( @$addresses ) {
         $resp{mappings}{$hash} = $self->{hashes}{$hash};
      }

      $req->respond_json( \%resp );
   }
   else {
      # Unknown algorithm provided
      $resp{error} = "Unknown algorithm";
      $resp{errcode} = "M_INVALID_PARAM";

      $req->respond_json( \%resp, code => 400 );
   }
}

sub store_invite
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   my $body = $req->body_from_json;
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
      address            => $address,
      medium             => $medium,
      room_id            => $room_id,
      sender             => $sender,
      token              => $token,
      guest_access_token => $body->{guest_access_token},
   };
   $resp{token} = $token;
   $resp{display_name} = "Bob";
   $resp{public_key} = $self->{keys}{"ed25519:0"};

   my $key_validity_url = "https://" . $self->name . "/_matrix/identity/v2/pubkey/isvalid";

   $resp{public_keys} = [
      {
         public_key => $self->{keys}{"ed25519:0"},
         key_validity_url => $key_validity_url,
      },
      {
         public_key => $self->{keys}{"ed25519:ephemeral"},
         key_validity_url => $key_validity_url,
      },
   ];

   $req->respond_json( \%resp );
}

sub get_validated_3pid
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   my $sid = $req->query_param( "sid" );
   unless( defined $sid and defined $self->{validated}{$sid} ) {
      $req->respond( HTTP::Response->new( 400, "Bad Request", [ Content_Length => 0 ] ) );
      return;
   }
   $resp{medium} = $self->{validated}{$sid}{medium};
   $resp{address} = $self->{validated}{$sid}{address};
   $resp{validated_at} = 0;
   $req->respond_json( \%resp );
}

# bind is a reserved method name
sub do_bind
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   my $body = $req->body_from_json;
   my $sid = $body->{sid};
   my $mxid = $body->{mxid};

   my $medium = $self->{validated}{$sid}{medium};
   my $address = $self->{validated}{$sid}{address};

   $self->bind_identity( undef, $medium, $address, $mxid );

   $resp{medium} = $medium;
   $resp{address} = $address;
   $resp{mxid} = $mxid;
   $resp{not_before} = 0;
   $resp{not_after} = 4582425849161;
   $resp{ts} = 0;

   sign_json( \%resp,
      secret_key => $self->{private_key},
      origin     => $self->name,
      key_id     => "ed25519:0",
   );

   $req->respond_json( \%resp );
}

sub unbind
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   my $body = $req->body_from_json;
   my $mxid = $body->{mxid};

   my $medium = $body->{threepid}{medium};
   my $address = $body->{threepid}{address};

   unless ($self->{bindings}{ join "\0", $medium, $address } eq $mxid ) {
      $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
      return;
   }

   delete($self->{bindings}{ join "\0", $medium, $address });

   $req->respond_json( \%resp );
}

sub bind_identity
{
   my $self = shift;
   my ( $hs_uribase, $medium, $address, $user, $before_resp ) = @_;

   # Correctly handle $user being either the scalar "user_id" or a ref of a User
   # object. (We can't use is_User because it hasn't been defined yet).
   my $user_id;
   if ( ref( $user ) ne "" ) {
      $user_id = $user->user_id;
   } else {
      $user_id = $user;
   }

   $self->{bindings}{ join "\0", $medium, $address } = $user_id;

   # Hash the medium, address and pepper and store it for later lookup requests
   my $str_to_hash = $address . " " . $medium . " " . $self->{lookup_pepper};
   my $hash = sha256( $str_to_hash );
   $hash = encode_base64url( $hash );
   $self->{hashes}{$hash} = $user_id;

   if( !defined $hs_uribase ) {
      return Future->done( 1 );
   }

   my %resp = (
      address => $address,
      medium  => $medium,
      mxid    => $user_id,
   );

   my $invites = $self->invites_for( $medium, $address );
   if( defined $invites ) {
      foreach my $invite ( @$invites ) {
         $invite->{mxid} = $user_id;
         $invite->{signed} = {
            mxid  => $user_id,
            token => $invite->{token},
         };
         $self->sign( $invite->{signed} );
      }
      $resp{invites} = $invites;
   }

   $self->sign( \%resp );

   $before_resp->() if defined $before_resp;

   $self->{http_client}->do_request_json(
      uri     => URI->new( "$hs_uribase/_matrix/federation/v1/3pid/onbind" ),
      method  => "POST",
      content => \%resp,
   );
}

sub lookup_identity
{
   my $self = shift;
   my ( $medium, $address ) = @_;

   my $mxid = $self->{bindings}{ join "\0", $medium, $address };
   if ( "email" eq $medium and defined $mxid ) {
      return $mxid;
   }

   return undef;
}

sub sign
{
   my $self = shift;

   my ( $to_sign, %opts ) = @_;

   my $key = $opts{ephemeral} ? $self->{ephemeral_private_key} : $self->{private_key};

   sign_json( $to_sign,
      secret_key => $key,
      origin     => $self->name,
      key_id     => "ed25519:0",
   );
}

sub invites_for
{
   my $self = shift;
   my ( $medium, $address ) = @_;

   return $self->{invites}{ join "\0", $medium, $address };
}

sub name
{
   my $self = shift;
   my $sock = $self->read_handle;
   sprintf "%s:%d", $sock->sockhostname, $sock->sockport;
}

1;
