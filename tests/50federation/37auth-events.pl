# Copyright 2017 New Vector Ltd
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

use Future::Utils qw( repeat );

test "Federation correctly handles state reset due to auth chain resolution",
   # We induce a state reset as follows: We have three power_levels events (A,
   # B, C). A is required for B, which in turn is required for C.
   #
   # We then send an event which references A in its auth_events.

   timeout => 300,

   requires => [ local_user_fixture(),
                 $main::INBOUND_SERVER,
                 federation_user_id_fixture(),
                 federation_user_id_fixture(),
                ],

   do => sub {
      my ( $synapse_user, $inbound_server, $sytest_user_id_a,
           $sytest_user_id_b) = @_;

      my $synapse_server_name = $synapse_user->http->server_name;
      my $outbound_client     = $inbound_server->client;
      my $sytest_server_name  = $inbound_server->server_name;
      my $datastore           = $inbound_server->datastore;

      my $room_alias = "#50fed-37auth-events:$sytest_server_name";

      # create the room.
      my $room = $datastore->create_room(
         creator => $sytest_user_id_a,
         alias   => $room_alias,
      );
      my $room_id = $room->{room_id};

      # create the first powerlevel event
      my $powerlevel_event_a = $room->create_event(
         sender    => $sytest_user_id_a,
         type      => "m.room.power_levels",
         state_key => "",
         content   => {
            users => {
               $sytest_user_id_a      => 100,
            },
         },
      );

      my $reset_event_id;

      # now get synapse to join
      return matrix_join_room(
         $synapse_user, $room_alias
      )->then( sub {
         # create and send the second powerlevel event
         my $ev = $room->create_event(
            sender    => $sytest_user_id_a,
            type      => "m.room.power_levels",
            state_key => "",
            content   => {
               users => {
                  $sytest_user_id_a      => 100,
                  $synapse_user->user_id => 100,
               },
            },
         );

         $outbound_client->send_event(
            event => $ev,
            destination => $synapse_server_name,
         )->then( sub {
            # wait for it to turn up on the synapse side
            await_sync_timeline_contains(
               $synapse_user, $room_id,
               check => sub {
                  my ( $event ) = @_;
                  return $event->{event_id} eq $ev->{event_id};
               },
               update_next_batch => 1,
            );
         });
      })->then( sub {
         # ... and the third powerlevel event, from the synapse side
         Future->needs_all(
            $inbound_server->await_event(
               "m.room.power_levels", $room_id, sub {1},
            )->then( sub {
               my ( $event ) = @_;
               log_if_fail( "Received power_levels event id " .
                  $event->{event_id} );
               $room->insert_event( $event );
               Future->done(1);
            }),

            matrix_put_room_state(
               $synapse_user,
               $room_id,
               type      => "m.room.power_levels",
               state_key => "",
               content   => {
                  ban   => 50,
                  users => {
                     $sytest_user_id_a      => 100,
                     $synapse_user->user_id => 100,
                  },
               },
            ),
         );
      })->then( sub {
         # now let's send an event from the sytest side which only references
         # the *first* powerlevel event in its auth_events

         my @auth_events = grep { defined } (
            $room->get_current_state_event( "m.room.create" ),
            $room->get_current_state_event( "m.room.join_rules" ),
            $room->get_current_state_event( "m.room.member", $sytest_user_id_a ),
            $powerlevel_event_a,
         );

         my $ev = $room->create_event(
            sender    => $sytest_user_id_a,
            type      => "m.room.message",
            content   => {
               body => "bzzt",
            },
            auth_events => SyTest::Federation::Room::make_event_refs( @auth_events ),
         );
         $reset_event_id = $ev->{event_id};

         log_if_fail( "Sent message event id " . $reset_event_id );

         $outbound_client->send_event(
            event => $ev,
            destination => $synapse_server_name,
         );
      })->then( sub {
         await_sync_timeline_contains( $synapse_user, $room_id, check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";

            assert_eq( $event->{content}{body}, "bzzt",
               'event content body' );

            return 1;
         });
      })->then( sub {
         # check the room state has been reset
         matrix_get_room_state(
            $synapse_user, $room_id, type => 'm.room.power_levels'
         )->then( sub {
            my ( $state ) = @_;
            log_if_fail( "power_levels in room state after reset", $state );
            assert_deeply_eq(
               $state, $powerlevel_event_a->{content}, "room state",
            );
            Future->done(0);
         });
      })->then( sub {
         # check that the context has been reset
         do_request_json_for( $synapse_user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/context/$reset_event_id",
            params  => { limit => 0 },
         )->then( sub {
            my ( $body ) = @_;
            log_if_fail( "context after reset", $body );
            Future->done(0);
         });
     });
   };
