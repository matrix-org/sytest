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
      my $mxid = $self->{bindings}{ join " ", $medium, $address };
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
   elsif( $path eq "/_matrix/identity/v2/hash_details" ) {
      $resp{lookup_pepper} = $self->{lookup_pepper};
      @resp{algorithms} = [ "none", "sha256" ];
      $req->respond_json( \%resp );
   }
   elsif( $path eq "/_matrix/identity/v2/lookup" ) {
      my ( $req ) = @_;

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
            $resp{bindings} = $self->{bindings};
            $resp{user_address} = $user_address;
            $resp{user_medium} = $user_medium;

            # We need to swap around medium and address here as it's stored "$medium $address"
            # locally, not "$address $medium"
            my $mxid = $self->{bindings}{ join " ", $user_medium, $user_address };

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
   elsif( $path eq "/_matrix/identity/api/v1/store-invite" ) {
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
      my $key = join " ", $medium, $address;
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

      my $key_validity_url = "https://" . $self->name . "/_matrix/identity/api/v1/pubkey/isvalid";

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
   elsif( $path eq "/_matrix/identity/api/v1/3pid/getValidated3pid" ) {
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
   elsif ( $path eq "/_matrix/identity/api/v1/3pid/bind" ) {
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
   elsif ( $path eq "/_matrix/identity/api/v1/3pid/unbind" ) {
      my $body = $req->body_from_json;
      my $mxid = $body->{mxid};

      my $medium = $body->{threepid}{medium};
      my $address = $body->{threepid}{address};

      unless ($self->{bindings}{ join " ", $medium, $address } eq $mxid ) {
         $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
         return;
      }

      delete($self->{bindings}{ join " ", $medium, $address });

      $req->respond_json( \%resp );
   }
   else {
      warn "Unexpected request to Identity Service for $path";
      $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
   }
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

   $self->{bindings}{ join " ", $medium, $address } = $user_id;

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

   my $mxid = $self->{bindings}{ join " ", $medium, $address };
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

   return $self->{invites}{ join " ", $medium, $address };
}

sub name
{
   my $self = shift;
   my $sock = $self->read_handle;
   sprintf "%s:%d", $sock->sockhostname, $sock->sockport;
}

1;
