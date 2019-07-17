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

use URI::Escape qw( uri_escape );

# send an event over federation and wait for it to turn up
sub send_and_await_event {
   my ( $outbound_client, $room, $sytest_user_id, $server_user, $server_name ) = @_;

   my $event = $room->create_and_insert_event(
      type => "m.room.message",
      sender  => $sytest_user_id,
      content => {
         body => "hi",
      },
   );

   my $event_id = $room->id_for_event( $event );

   Future->needs_all(
      $outbound_client->send_event(
         event => $event,
         destination => $server_name,
      ),
      await_sync_timeline_contains(
         $server_user, $room->room_id, check => sub {
            $_[0]->{event_id} eq $event_id
         }
      ),
   );
}


test "Inbound federation ignores redactions from invalid servers room > v3",
   requires => [
      $main::OUTBOUND_CLIENT,
      $main::INBOUND_SERVER,
      $main::HOMESERVER_INFO[0],
      local_user_and_room_fixtures(
         room_opts => { room_version => "5" },
      ),
      federation_user_id_fixture()
   ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my ( $msg_event_id, $redaction_event_id, $room );

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         ( $room ) = @_;

         Future->needs_all(
            matrix_send_room_text_message( $creator, $room_id, body => "Hello" )
               -> on_done( sub {
                  ( $msg_event_id ) = @_;
                  log_if_fail "Sent message: $msg_event_id";
               }),
            $inbound_server->await_event( "m.room.message", $room_id, sub {1} ),
         );
      })->then( sub {
         # now spoof a redaction from our side.
         my $event = $room->create_and_insert_event(
            type => "m.room.redaction",
            sender  => $user_id,
            redacts => $msg_event_id,
            content => {},
         );

         log_if_fail "Sending fake redaction", $event;

         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         );
      })->then( sub {
         # send a regular message event to act as a sentinel
         send_and_await_event( $outbound_client, $room, $user_id, $creator, $first_home_server );
      })->then( sub {
         # re-check the original event
         do_request_json_for( $creator,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/event/${ \uri_escape( $msg_event_id ) }",
         );
      })->then( sub {
         my ( $ev ) = @_;
         log_if_fail "event after first fake redaction", $ev;

         assert_deeply_eq( $ev->{unsigned}->{redacted_by}, undef, "event redacted by fake redaction" );
         assert_eq( $ev->{content}->{body}, "Hello", "event content modified by fake redaction" );

         # a legitimate redaction
         Future->needs_all(
            matrix_redact_event_synced( $creator, $room_id, $msg_event_id )
               ->on_done( sub {
                  ( $redaction_event_id ) = @_;
               }),
            $inbound_server->await_event( "m.room.redaction", $room_id, sub {1} ),
         );
      })->then( sub {
         # if we now fetch the event, it should be redacted by the redaction event
         do_request_json_for( $creator,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/event/${ \uri_escape( $msg_event_id ) }",
         );
      })->then( sub {
         my ( $ev ) = @_;
         log_if_fail "event after redaction", $ev;
         assert_eq( $ev->{unsigned}->{redacted_by}, $redaction_event_id, "redacted by wrong event" );

         # spoof another redaction
         my $event = $room->create_and_insert_event(
            type => "m.room.redaction",
            sender  => $user_id,
            redacts => $msg_event_id,
            content => {},
           );

         my $fake_redaction_event_id = $room->id_for_event( $event );

         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         );
      })->then( sub {
         # send another regular message
         send_and_await_event( $outbound_client, $room, $user_id, $creator, $first_home_server );
      })->then( sub {
         # re-check the original event
         do_request_json_for( $creator,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/event/${ \uri_escape( $msg_event_id ) }",
         );
      })->then( sub {
         my ( $ev ) = @_;
         log_if_fail "event after second fake redaction", $ev;
         assert_eq( $ev->{unsigned}->{redacted_by}, $redaction_event_id );

         Future->done
      });
   };
