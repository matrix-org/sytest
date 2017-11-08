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

test "Any user can send the first power_levels event in a room",
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

      my $room_alias = "#50fed-40power-levels:$sytest_server_name";

      # create the room.
      my $room = $datastore->create_room(
         creator => $sytest_user_id_a,
         alias   => $room_alias,
      );
      my $room_id = $room->{room_id};

      # now get synapse to join
      return matrix_join_room(
         $synapse_user, $room_alias
      )->then( sub {
         # now the synapse user ought to be able to send a power_levels event
         Future->needs_all(
            $inbound_server->await_event(
               "m.room.power_levels", $room_id, sub {1},
            )->then( sub {
               my ( $event ) = @_;
               log_if_fail "Received power_levels event", $event;
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
                     $synapse_user->user_id => 1000,
                  },
               },
            ),
         );
     });
  };
