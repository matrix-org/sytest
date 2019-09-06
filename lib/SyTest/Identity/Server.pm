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

# Perpetually correct access token for authenticating with v2 Identity Service API endpoints.
# v2 endpoint calls to this identity server should include this value for their
# `id_access_token` parameter
my $ID_ACCESS_TOKEN = "swordfish";

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

=head2

   $self->rotate_keys();

Creates new ed25519 public/private key pairs for this server.

=cut

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

=head2

Handles incoming HTTP requests to this server.

=cut

sub on_request
{
   my $self = shift;
   my ( $req ) = @_;

   my $path = $req->path;
   my $key_name;

   if(
      $path eq "/_matrix/identity/api/v1/pubkey/isvalid" or
      $path eq "/_matrix/identity/v2/pubkey/isvalid"
   ) {
      $self->on_is_valid( $req );
   }
   elsif( ( $key_name ) = $path =~ m#^/_matrix/identity/api/v1/pubkey/([^/]*)$# ) {
      $self->on_pubkey( $req, $key_name );
   }
   elsif( ( $key_name ) = $path =~ m#^/_matrix/identity/v2/pubkey/([^/]*)$# ) {
      $self->check_v2( $req ) and $self->on_pubkey( $req, $key_name );
   }
   elsif( $path eq "/_matrix/identity/api/v1/lookup" ) {
      $self->on_v1_lookup( $req );
   }
   elsif( $path eq "/_matrix/identity/v2/lookup" ) {
      $self->check_v2( $req ) and $self->on_v2_lookup( $req );
   }
   elsif( $path eq "/_matrix/identity/v2/hash_details" ) {
      $self->check_v2( $req ) and $self->on_hash_details( $req );
   }
   elsif( $path eq "/_matrix/identity/api/v1/store-invite" ) {
      $self->on_store_invite( $req );
   }
   elsif( $path eq "/_matrix/identity/v2/store-invite" ) {
      $self->check_v2( $req ) and $self->on_store_invite( $req );
   }
   elsif( $path eq "/_matrix/identity/api/v1/3pid/getValidated3pid" ) {
      $self->on_get_validated_3pid( $req );
   }
   elsif( $path eq "/_matrix/identity/v2/3pid/getValidated3pid" ) {
      $self->check_v2( $req ) and $self->on_get_validated_3pid( $req );
   }
   elsif ( $path eq "/_matrix/identity/api/v1/3pid/bind" ) {
      $self->on_bind( $req );
   }
   elsif ( $path eq "/_matrix/identity/v2/3pid/bind" ) {
      $self->check_v2( $req ) and $self->on_bind( $req );
   }
   elsif (  # v2 /unbind does not require an id_access_token param
      $path eq "/_matrix/identity/v2/3pid/unbind" or
      $path eq "/_matrix/identity/api/v1/3pid/unbind"
   ) {
      $self->on_unbind( $req );
   }
   else {
      warn "Unexpected request to Identity Service for $path";
      $req->respond( HTTP::Response->new( 404, "Not Found", [ Content_Length => 0 ] ) );
   }
}

=head2 check_v2

   $self->check_v2 ( $req ) and do_something_else();

A helper method that takes an HTTP request and checks if an C<id_access_token> parameter
matching C<$ID_ACCESS_TOKEN> is present in either the query parameters or the top-level JSON of
the request body.

Returns C<0> or C<1> depending on whether a correct C<id_access_token> value was found.

Responds to the HTTP request with an error message if no C<id_access_token> value was found.

=cut

sub check_v2
{
   # Check that either an id_access_token query parameter or JSON body key exists in the req
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   if (
      $req->query_param("id_access_token") and
      $req->query_param("id_access_token") eq $ID_ACCESS_TOKEN
   ) {
      # We found it!
      return 1
   }

   # Check the JSON body for the token. This isn't required for all endpoints so only try if
   # the request has a body
   my $body = eval { $req->body_from_json };

   if (
      $body and
      $body->{id_access_token} and
      $body->{id_access_token} eq $ID_ACCESS_TOKEN
   ) {
      # We found it!
      return 1
   }

   # Couldn't find an access token
   $resp{error} = "Missing id_access_token parameter";
   $resp{errcode} = "M_MISSING_PARAM";
   $req->respond_json( \%resp, code => 400 );
   return 0
}

=head2 on_is_valid

   $self->on_is_valid( $req );

Given a HTTP request, check that the value of the public_key query parameter matches a key in
the C<$self->{keys}> dictionary.

Responds to the HTTP request with JSON body C<{"valid": true}> or C<{"valid": false}> depending
on whether a match was found.

=cut

sub on_is_valid
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   my $valid = any { $_ eq $req->query_param("public_key") } values %{ $self->{keys} };
   $resp{valid} = $valid ? JSON::true : JSON::false;
   $req->respond_json( \%resp );
}

=head2

   $self->validate_identity( $medium, $address, $client_secret );

Validates a C<medium>, C<address> combo against a given C<client_secret>.

Example:

   $self->validate_identity( "email", "heyitsfred@example.com", "apples" );

Returns the session ID corresponding to the given parameters if one is found.

=cut

sub validate_identity
{
   my $self = shift;
   my ( $medium, $address, $client_secret ) = @_;
   my $sid = "session_${\ $self->{sid}++ }";
   $self->on_pubkey( $req, $key_name );
   $self->{validated}{$sid} = {
      medium       => $medium,
      address      => $address,
   };
   return $sid;
}

=head2

   $self->on_pubkey( $req, $key_name );

Given a HTTP request and a key name, return the public key corresponding to that key name if
known.

Responds to the HTTP request with JSON body C<{"public_key": "some_public_key"}> if a public
key is found, otherwise return an empty body.

=cut

sub on_pubkey
{
   my $self = shift;
   my ( $req, $key_name ) = @_;
   my %resp;

   if( defined $self->{keys}{$key_name} ) {
      $resp{public_key} = $self->{keys}{$key_name};
   }
   $req->respond_json( \%resp );
}

=head2

   $self->on_v1_lookup( $req );

Given a HTTP request containing C<medium> and C<address> query parameters, look up an
address/medium combination in the server.

If found, this method will respond to the request with a signed JSON object containing the
C<medium>, C<address> and C<mxid> of the found user.

If not found, the request will be sent an empty JSON body.

=cut

sub on_v1_lookup
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

=head2

   $self->on_hash_details( $req );

Given a HTTP request, this function will respond with a JSON body with a C<lookup_pepper>
string containing the server's lookup pepper, and a C<algorithms> array containing all of the
lookup algorithms the server supports.

=cut

sub on_hash_details
{
   my $self = shift;
   my ( $req ) = @_;
   my %resp;

   $resp{lookup_pepper} = $self->{lookup_pepper};
   @resp{algorithms} = [ "none", "sha256" ];
   $req->respond_json( \%resp );
}

=head2

   $self->on_v2_lookup( $req );

Given a HTTP request containing C<algorithm>, C<pepper> and C<addresses> fields in its JSON
body, perform a v2 lookup. This involves checking the algorithm that was specified, and whether
it matches one the identity server supports. Then depending on the algorithm, a lookup of the
data in the C<addresses> field is carried out.

If the request contains an algorithm that the identity server does not support, it will be
responded to with a C<400 M_INVALID_PARAM>. If the request contains a pepper that doesn't match
the server's, it will be responded to with a C<400 M_INVALID_PEPPER>. Otherwise, the request
will be responded to with a JSON body with a C<mappings> field, which contains the results of
the lookup on the given C<addresses>.

=cut

sub on_v2_lookup
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
         if ( scalar( @address_medium ) != 2 ) {
            $resp{error} = "Address is not two strings separated by a space: ${address}";
            $resp{errcode} = "M_UNKNOWN";

            $req->respond_json( \%resp, code => 400 );
            return;
         }

         # Parse the medium and address from the string
         my ( $user_address, $user_medium ) = @address_medium;

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

=head2

   $self->on_store_invite( $req );

Given a HTTP request with a JSON body containing C<medium>, C<address>, C<sender> and
C<room_id> keys, create and store an invite containing them.

Responds to the HTTP request with C<token>, C<display_name> and public_keys.

=cut

sub on_store_invite
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

=head2

   $self->on_get_validated_3pid( $req );

Given a HTTP request with a session ID C<sid> query parameter, respond with C<medium>,
C<address> and C<validated_at> JSON body fields corresponding to the session ID.

If the session ID is unknown, respond with a HTTP C<400>.

=cut

sub on_get_validated_3pid
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

=head2

   $self->on_bind( $req );

Given a HTTP request containing session ID C<sid> and Matrix ID C<mxid> JSON body fields, bind
the medium and address corresponding to the session ID to the given Matrix ID.

Responds to the HTTP request with a signed JSON body containing <medium>, C<address>, C<mxid>,
 C<not_before>, C<not_after> and C<ts> fields.

=cut

sub on_bind
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

=head2

   $self->on_unbind( $req );

Given a HTTP request containing a Matrix ID C<mxid, and a threepid dictionary C<threepid>,
which itself has C<medium> and C<address> fields, remove the binding from the server.

If no binding is found, respond to the HTTP request with a C<404 Not Found> error.

=cut

sub on_unbind
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

=head2

   $self->bind_identity( $hs_uribase, $medium, $address, $user, $before_resp );

Shortcut to creating a new threepid identity binding, and calling the C<onbind> callback of a
homeserver specified by C<hs_uribase>.

Example:

   $self->bind_identity( undef, "email", $invitee_email, $invitee_mxid );

Store the C<medium> and C<address> as well as the hash of the address for v2 lookup. Finally,
call the C</_matrix/federation/v1/3pid/onbind> endpoint of the HS specified by C<hs_uribase>
(if defined).

If C<$before_resp> is a function, that function will be executed before the C<onbind> call is
made.

=cut

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

=head2

   $self->lookup_identity( $medium, $address );

Shortcut for finding the MXID that's been previously bound to the C<medium>, C<address> combo.

Example:

   $self->lookup_identity( "email", "bob@example.com" );

Returns the matching Matrix ID, or C<undef> if one is not found.

=cut

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

=head2

   $self->sign( $to_sign, %opts );

Sign some data B<in-place> using the server's private key. Setting C<ephemeral> to C<1> will
use the server's ephemeral private key for signing instead.

Example:

   my %req = (
      mxid   => $invitee->user_id,
      sender => $inviter->user_id,
      token  => $token,
   );

   $self->sign( \%req, ephemeral => 1);

=cut

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

=head2

   $self->invites_for( $medium, $address );

Retrieve the invites for a C<medium>, C<address> pair.

Example:

   my $invites = $self->invites_for( "email", "threeheadedmonkey@island.com" );

Returns a reference to an array of invites that correspond to the given C<medium>, C<address>
pair.

=cut

sub invites_for
{
   my $self = shift;
   my ( $medium, $address ) = @_;

   return $self->{invites}{ join "\0", $medium, $address };
}

=head2

   $self->get_access_token();

Returns the access token for this server. Required for making calls to authenticated V2
Identity Service endpoints.

Example:

   my $access_token = $self->get_access_token();

=cut

sub get_access_token
{
   return $ID_ACCESS_TOKEN;
}

=head2

   $self->name():

Return a string made up of the server's hostname and port, separated by a colon.

=cut

sub name
{
   my $self = shift;
   my $sock = $self->read_handle;
   sprintf "%s:%d", $sock->sockhostname, $sock->sockport;
}

1;
