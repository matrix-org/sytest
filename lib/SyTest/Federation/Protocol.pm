# Copyright 2019 The Matrix.org Foundation C.I.C
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package SyTest::Federation::Protocol;

use strict;
use warnings;

use Digest::SHA qw( sha256 );
use MIME::Base64 qw( encode_base64url );

use Protocol::Matrix qw(
   redacted_event
   encode_json_for_signing
   encode_base64_unpadded
);

use Carp;

use Exporter 'import';
our @EXPORT_OK = qw(
   hash_event
   id_for_event
);

=head2 hash_event

    $hash = hash_event( $event );

Calculates the reference hash of an event.

=cut

sub hash_event
{
   my ( $event ) = @_;
   croak "Require an event" unless ref $event eq 'HASH';
   my $redacted = redacted_event( $event );
   delete $redacted->{signatures};
   delete $redacted->{age_ts};
   delete $redacted->{unsigned};

   my $bytes_to_hash = encode_json_for_signing( $redacted );
   return sha256( $bytes_to_hash );
}


=head2 id_for_event

    $event_id = id_for_event( $event, $room_version );

Fetches or calculates the event_id for the given event

=cut

sub id_for_event
{
   my ( $event, $room_version ) = @_;

   $room_version //= 1;

   if( $room_version eq '1' || $room_version eq '2' ) {
      my $event_id = $event->{event_id};
      die "event with no event_id" if not $event_id;
      return $event_id;
   }

   my $event_hash = hash_event( $event );

   # room v3 uses the unpadded-base64-encoded hash
   if( $room_version eq '3' ) {
      return '$' . encode_base64_unpadded( $event_hash );
   }

   # other rooms use the url-safe unpadded-base64-encoded hash
   return '$' . encode_base64url( $event_hash );
}
