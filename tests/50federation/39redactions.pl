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

test "Inbound federation ignores redactions from invalid servers room > v3",
   requires => [
      $main::OUTBOUND_CLIENT,
      $main::INBOUND_SERVER,
      federated_rooms_fixture(
         room_opts => { room_version => "5" },
      ),
   ],

   do => sub {
      my ( $outbound_client, $inbound_server, $creator, $user_id, $room ) = @_;
      my $first_home_server = $creator->server_name;
      my $room_id = $room->room_id;

      my ( $msg_event_id, $redaction_event_id );

      Future->needs_all(
         matrix_send_room_text_message( $creator, $room_id, body => "Hello" )
            -> on_done( sub {
               ( $msg_event_id ) = @_;
               log_if_fail "Sent message: $msg_event_id";
            }),
         $inbound_server->await_event( "m.room.message", $room_id, sub {1} ),
      )->then( sub {
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
         send_and_await_event( $outbound_client, $room, $creator, sender => $user_id );
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
         send_and_await_event( $outbound_client, $room, $creator, sender => $user_id );
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


my $creator_fixture = local_user_fixture();

test "An event which redacts an event in a different room should be ignored",
   requires => [
      $main::OUTBOUND_CLIENT,
      federated_rooms_fixture(
         room_count => 2,
      ),
   ],

   do => sub {
      my ( $outbound_client, $creator, $user_id, $room_1, $room_2 ) = @_;
      my $first_home_server = $creator->server_name;

      my ( $msg_event_id, $redaction_event_id );

      # send an event in one room
      my $event = $room_1->create_and_insert_event(
         type => "m.room.message",
         sender  => $user_id,
         content => {
            body => "hi",
         },
      );

      $msg_event_id = $room_1->id_for_event( $event );

      Future->needs_all(
         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         ),
         await_sync_timeline_contains(
            $creator, $room_1->room_id, check => sub {
               $_[0]->{event_id} eq $msg_event_id
            }
         ),
      )->then( sub {
         # now send an event in another room which claims to redact it
         my $event = $room_2->create_and_insert_event(
            type     => "m.room.redaction",
            sender   => $user_id,
            content  => {},
            redacts  => $msg_event_id,
         );

         $redaction_event_id = $room_2->id_for_event( $event );

         log_if_fail "Sending redaction", $event;

         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         );
      })->then( sub {
         # send another regular event as a sentinel, and make sure the redaction doesn't
         # turn up.

         my $event = $room_2->create_and_insert_event(
            type => "m.room.message",
            sender  => $user_id,
            content => {
               body => "sentinel",
            },
         );

         my $event_id = $room_2->id_for_event( $event );

         Future->needs_all(
            $outbound_client->send_event(
               event => $event,
               destination => $first_home_server,
            ),
            await_sync_timeline_contains(
               $creator, $room_2->room_id, check => sub {
                  my ( $ev ) = @_;
                  if ( $ev->{event_id} eq $redaction_event_id ) {
                     log_if_fail "Received redaction :/", $ev;
                     die "redaction was not rejected";
                  }
                  return $ev->{event_id} eq $event_id;
               }
            )
         );
      })->then( sub {
         # now fetch the original event again, and check it's not redacted
         matrix_get_event( $creator, $room_1->room_id, $msg_event_id );
      })->then( sub {
         my ( $fetched ) = @_;

         log_if_fail "Fetched original message event", $fetched;
         assert_json_keys( $fetched->{content}, qw( body ) );
         assert_eq( $fetched->{content}->{body}, "hi" );
         Future->done;
      });
   };

test "Inbound federation ignores redactions from invalid servers room > v3",
   requires => [
      $main::OUTBOUND_CLIENT,
      federated_rooms_fixture( room_opts => { room_version => "1" } ),
      federation_user_id_fixture(),
   ],

   do => sub {
      my ( $outbound_client, $creator, $user_id, $room ) = @_;
      my $first_home_server = $creator->server_name;

      my $event_id = '$lolredact:' . $outbound_client->server_name;

      # create an event which claims to redact itself.
      my $event = $room->create_and_insert_event(
         event_id => $event_id,
         type     => "m.room.redaction",
         sender   => $user_id,
         redacts  => $event_id,
         content  => {},
      );

      log_if_fail "Sending redaction inception", $event;

      $outbound_client->send_event(
         event => $event,
         destination => $first_home_server,
      )->then( sub {
         await_sync_timeline_contains(
            $creator, $room->room_id, check => sub {
               $_[0]->{event_id} eq $event_id
            }
         )
      });
   };

test "A pair of events which redact each other should be ignored",
   requires => [
      $main::OUTBOUND_CLIENT,
      federated_rooms_fixture( room_opts => { room_version => "1" }),
      federation_user_id_fixture(),
   ],

   do => sub {
      my ( $outbound_client, $creator, $user_id, $room ) = @_;
      my $first_home_server = $creator->server_name;

      my $redaction1 = $outbound_client->{datastore}->next_event_id( "redaction1" );
      my $redaction2 = $outbound_client->{datastore}->next_event_id( "redaction2" );

      my $event1 = $room->create_and_insert_event(
         event_id => $redaction1,
         type     => "m.room.redaction",
         sender   => $user_id,
         redacts  => $redaction2,
         content  => {},
      );

      log_if_fail "Sending first redaction", $event1;

      $outbound_client->send_event(
         event => $event1,
         destination => $first_home_server,
      )->then( sub {
         my $event2 = $room->create_and_insert_event(
            event_id => $redaction2,
            type     => "m.room.redaction",
            sender   => $user_id,
            redacts  => $redaction1,
            content  => {},
         );

         log_if_fail "Sending second redaction", $event2;

         $outbound_client->send_event(
            event => $event2,
            destination => $first_home_server,
         );
      })->then( sub {
         await_sync_timeline_contains(
            $creator, $room->room_id, check => sub {
               $_[0]->{event_id} eq $redaction2
            }
         )
      });
   };


