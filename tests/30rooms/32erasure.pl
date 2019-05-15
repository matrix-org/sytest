# Copyright 2018 New Vector Ltd
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

use List::Util qw( first );

test "Only original members of the room can see messages from erased users",
   requires => [ local_user_and_room_fixtures(), local_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $member, $joiner ) = @_;

      my $message_id;
      matrix_join_room_synced( $member, $room_id )
      ->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "body1" );
      })->then( sub {
         ( $message_id ) = @_;
         matrix_join_room_synced( $joiner, $room_id );
      })->then( sub {
         # now both users should see the message event
         matrix_sync( $joiner, limit => 4 );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         my $events = $room->{timeline}->{events};
         log_if_fail "messages for joining user before erasure", $events;

         my $e = first { $_->{event_id} eq $message_id } @$events;
         assert_eq( $e->{type}, "m.room.message", "event type" );
         assert_eq( $e->{content}->{body}, "body1", "event content body" );

         matrix_deactivate_account( $creator, erase => JSON::true );
      })->then( sub {
         # now the original member should see the message event, but the joiner
         # should see a redacted version
         matrix_sync( $member );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         my $events = $room->{timeline}->{events};
         log_if_fail "messages for original member after erasure", $events;

         my $e = first { $_->{event_id} eq $message_id } @$events;
         assert_eq( $e->{type}, "m.room.message", "event type" );
         assert_eq( $e->{content}->{body}, "body1", "event content body" );

         matrix_sync( $joiner );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         my $events = $room->{timeline}->{events};
         log_if_fail "messages for joining user after erasure", $events;

         my $e = first { $_->{event_id} eq $message_id } @$events;
         assert_eq( $e->{type}, "m.room.message", "event type" );
         assert_deeply_eq( $e->{content}, {}, "event content" );

         Future->done(1);
      });
   };
