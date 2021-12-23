#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2015 -- leonerd@leonerd.org.uk

package Protocol::Matrix;

use strict;
use warnings;
use 5.014; # s///r

our $VERSION = '0.02.sytest20211223';

use Carp;

use Crypt::Ed25519;
use Digest::SHA qw( sha256 );
use JSON;
use MIME::Base64 qw( encode_base64 decode_base64 );

use Exporter 'import';
our @EXPORT_OK = qw(
   encode_json_for_signing
   encode_base64_unpadded
   decode_base64

   sign_json signed_json
   verify_json_signature

   redact_event redacted_event

   sign_event_json signed_event_json
   verify_event_json_signature
);

my $json_canon = JSON->new
                     ->convert_blessed
                     ->canonical
                     ->utf8;

=head1 NAME

C<Protocol::Matrix> - Helper functions for the Matrix protocol

=head1 DESCRIPTION

This module provides some helper functions for implementing a F<matrix> client
or server. Currently it only contains a few base-level functions to assist
with signing and verifying signatures on federation-level events.

=cut

=head1 FUNCTIONS

=cut

=head2 encode_json_for_signing

   $json = encode_json_for_signing( $data )

Encodes a given HASH reference as Canonical JSON, having removed the
C<signatures> and C<unsigned> keys if present. This is the first step
towards signing it or verifying an embedded signature in it. The hash
referred to by C<$data> remains unmodified by this function.

=cut

sub encode_json_for_signing
{
   my ( $d ) = @_;

   # Remove keys that don't get signed
   my %to_sign = %$d;
   delete $to_sign{signatures};
   delete $to_sign{unsigned};

   return $json_canon->encode( \%to_sign );
}

=head2 encode_base64_unpadded

   $base64 = encode_base64( $bytes )

Returns a character string containing the Base-64 encoding of the given bytes,
with no internal linebreaks and no trailing padding.

=cut

sub encode_base64_unpadded
{
   return encode_base64( $_[0], "" ) =~ s/=+$//r;
}

=head2 decode_base64

   $bytes = decode_base64( $base64 )

Returns a byte string containing the bytes obtained by decoding the given
character string. This is re-exported from L<MIME::Base64> for convenience.

=cut

=head2 sign_json

   sign_json( $data, secret_key => $key, origin => $name, key_id => $id )

or:

   sign_json( $data,
      eddsa_secret_key => $secret_key,
      eddsa_public_key => $public_key,
      origin => $name,
      key_id => $id,
   )

Modifies the given HASH reference in-place to add a signature. This signature
is created from the given key, and annotated as being from the given origin
name and key ID. Existing signatures already in the hash are not disturbed.

The key can be specified in one of two ways: either with C<secret_key>, in
which case the C<$key> should be a plain byte string or L<Data::Locker> object
obtained from L<Crypt::NaCl::Sodium::sign>'s C<keypair> method; or with
C<eddsa_secret_key> with a key returned by
L<Crypt::Ed25519::eddsa_secret_key>. In the latter case C<eddsa_public_key> is
optional, and the public key will be derived if not given.

=cut

sub sign_json
{
   my ( $data, %args ) = @_;

   my $origin = $args{origin} or croak "Require an 'origin'";
   my $key_id = $args{key_id} or croak "Require a 'key_id'";

   my ( $secret_key, $public_key );
   if( exists $args{secret_key} ) {
      my $key = $args{secret_key};

      # libsodium's "private keys" are actually 64-byte tuples of (seed, public key).
      # fish them out for use with eddsa_sign.
      length( $key ) == 64 or croak "secret_key must be 64 bytes";
      $secret_key = substr( $key, 0, 32 );
      $public_key = substr( $key, 32, 32 );
   } elsif( exists $args{eddsa_secret_key} ) {
      $secret_key = $args{eddsa_secret_key};
      $public_key = $args{eddsa_public_key} // Crypt::Ed25519::eddsa_public_key( $secret_key );
   } else {
       croak "Require a secret key";
   }

   my $signature = Crypt::Ed25519::eddsa_sign( encode_json_for_signing( $data ), $public_key, $secret_key );

   $data->{signatures}{$origin}{$key_id} = encode_base64_unpadded( $signature );
}

=head2 signed_json

   my $data = signed_json( $data, ... )

Returns a new HASH reference by cloning the original and applying
L</sign_json> to it. The originally-passed data is unmodified. Takes the same
arguments as L</sign_json>.

=cut

sub signed_json
{
   my ( $data, @args ) = @_;
   sign_json( $data = { %$data }, @args );
   return $data;
}

=head2 verify_json_signature

   verify_json_signature( $data, public_key => $key, origin => $name, key_id => $id )

Inspects the given HASH reference to check that it contains a signature from
the named origin, with the given key ID, and that it is actually valid.

This function does not return an interesting value; all failures are indicated
by thrown exceptions. If no exception is thrown, it can be presumed valid.

=cut

sub verify_json_signature
{
   my ( $data, %args ) = @_;

   my $key = $args{public_key} or croak "Require a 'public_key'";

   my $origin = $args{origin} or croak "Require an 'origin'";
   my $key_id = $args{key_id} or croak "Require a 'key_id'";

   $data->{signatures} or
      croak "No 'signatures'";
   $data->{signatures}{$origin} or
      croak "No signatures from '$origin'";

   my $signature = $data->{signatures}{$origin}{$key_id} or
      croak "No signature from '$origin' using key '$key_id'";

   my $decoded = decode_base64( $signature );

   # Crypt::Ed25519::verify ignores garbage at the end of the
   # signature, so let's check that now.
   length( $decoded ) == 64 or
     croak "Invalid signature";

   Crypt::Ed25519::verify( encode_json_for_signing( $data ), $key, $decoded ) or
      croak "Signature verification failed";
}

=head2 redact_event

   redact_event( $event )

Modifies the given HASH reference in-place to apply the transformation given
by the Matrix Event Redaction specification.

=cut

my %ALLOWED_KEYS = map { $_ => 1 } qw(
   auth_events
   depth
   event_id
   hashes
   membership
   origin
   origin_server_ts
   prev_events
   prev_state
   room_id
   sender
   signatures
   state_key
   type
);

my %ALLOWED_CONTENT_BY_TYPE = (
   "m.room.aliases"            => [qw( aliases )],
   "m.room.create"             => [qw( creator )],
   "m.room.history_visibility" => [qw( history_visibility )],
   "m.room.join_rules"         => [qw( join_rule )],
   "m.room.member"             => [qw( membership )],
   "m.room.power_levels"       => [qw(
      users users_default events events_default state_default ban kick redact
   )],
);

sub redact_event
{
   my ( $event ) = @_;

   defined( my $type = $event->{type} ) or
      croak "Event requires a 'type'";

   my $old_content = delete $event->{content};
   my $old_unsigned = delete $event->{unsigned};

   $ALLOWED_KEYS{$_} or delete $event->{$_} for keys %$event;

   my $new_content = $event->{content} = {};

   if( my $allowed_content_keys = $ALLOWED_CONTENT_BY_TYPE{$type} ) {
      exists $old_content->{$_} and $new_content->{$_} = $old_content->{$_} for
         @$allowed_content_keys;
   }

   $event->{unsigned}{age_ts} = $old_unsigned->{age_ts} if exists $old_unsigned->{age_ts};
}

sub redacted_event
{
   my ( $event ) = @_;
   redact_event( $event = { %$event } );
   return $event;
}

=head2 sign_event_json

   sign_event_json( $data, ... )

Modifies the given HASH reference in-place to add a hash and signature,
presuming it to be a Matrix event structure. This operates in a fashion
analogous to L</sign_json>.

=cut

sub sign_event_json
{
   my ( $event, %args ) = @_;

   my $origin = $args{origin} or croak "Require an 'origin'";
   my $key_id = $args{key_id} or croak "Require a 'key_id'";

   # 'hashes' records the original unredacted version
   {
      my %event_without_hashes = %$event; delete $event_without_hashes{hashes};
      my $bytes_to_hash = encode_json_for_signing( \%event_without_hashes );

      $event->{hashes}{sha256} = encode_base64_unpadded( sha256( $bytes_to_hash ) );
   }

   # Signature is of redacted version
   sign_json( my $signed = redacted_event( $event ), %args );

   $event->{signatures} = $signed->{signatures};
}

=head2 signed_event_json

   my $event = signed_event_json( $event, ... )

Returns a new HASH reference by cloning the original and applying
L</sign_event_json> to it. The originally-passed data is unmodified. Takes the
same arguments as L</sign_event_json>.

=cut

sub signed_event_json
{
   my ( $event, @args ) = @_;
   sign_event_json( $event = { %$event }, @args );
   return $event;
}

=head2 verify_event_json_signature

   verify_event_json_signature( $event, public_key => $key, origin => $name, key_id => $id )

=cut

sub verify_event_json_signature
{
   my ( $event, @args ) = @_;

   verify_json_signature( redacted_event( $event ), @args );
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
