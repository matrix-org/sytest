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

test "Remote servers cannot set power levels in rooms without existing powerlevels",

   requires => [ local_user_fixture(),
                 $main::INBOUND_SERVER,
                 federation_user_id_fixture(),
                ],

   do => sub {
      my ( $synapse_user, $inbound_server, $sytest_user_id_a) = @_;

      my $synapse_server_name = $synapse_user->http->server_name;
      my $outbound_client     = $inbound_server->client;
      my $sytest_server_name  = $inbound_server->server_name;
      my $datastore           = $inbound_server->datastore;

      my $room_alias = "#50fed-40power-levels:$sytest_server_name";

      # create a room with no power levels event.
      my $room = $datastore->create_room(
         creator => $sytest_user_id_a,
         alias   => $room_alias,
      );
      my $room_id = $room->{room_id};

      # now get synapse to join
      return matrix_join_room(
         $synapse_user, $room_alias
      )->then( sub {
         # now the synapse user ought not to be able to send a power_levels event
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
         )->main::expect_http_403;
     });
  };


test "Remote servers should reject attempts by non-creators to set the power levels",

   requires => [ $main::OUTBOUND_CLIENT,
                 $main::INBOUND_SERVER,
                 $main::HOMESERVER_INFO[0],
                 local_user_fixture(),
                 federation_user_id_fixture(),
                 federation_user_id_fixture(),
                ],

   do => sub {
      my ( $outbound_server, $inbound_server, $hs_info,
           $synapse_user, $sytest_user_id_a, $sytest_user_id_b ) = @_;

      my $synapse_server_name = $synapse_user->http->server_name;
      my $outbound_client     = $inbound_server->client;
      my $sytest_server_name  = $inbound_server->server_name;
      my $datastore           = $inbound_server->datastore;

      my $room_alias = "#50fed-40power-levels:$sytest_server_name";

      # create a room with no power levels event, but joins from two sytest users.
      my $room = $datastore->create_room(
         creator => $sytest_user_id_a,
         alias   => $room_alias,
      );
      my $room_id = $room->{room_id};

      $room->create_and_insert_event(
         type => "m.room.member",
         content     => { membership => "join" },
         sender      => $sytest_user_id_b,
         state_key   => $sytest_user_id_b,
      );

      # now get synapse to join
      return matrix_join_room_synced(
         $synapse_user, $room_alias
      )->then( sub {
         # check that synapse sees a join from user id b, and no power_levels.
         matrix_get_room_state_by_type( $synapse_user, $room_id );
      })->then( sub {
         my ( $state ) = @_;
         $state->{'m.room.power_levels'} and die 'found power_levels in initial room state';
         $state->{'m.room.member'}->{ $sytest_user_id_b }
            or die "no membership for $sytest_user_id_b";

         # now synapse should reject an attempt by user b to set the power levels.
         my $pl = $room->create_and_insert_event(
            sender    => $sytest_user_id_b,
            type      => "m.room.power_levels",
            state_key => "",
            content   => {
               users => {
                  $sytest_user_id_b => 100,
               },
            },
         );

         $outbound_client->send_event(
            event => $pl,
            destination => $hs_info->server_name,
         );
      })->then( sub {
         # check that synapse still doesn't have a PL event. Annoyingly we need
         # to give it a few seconds to turn up.
         delay( 5 )
      })->then( sub {
         matrix_get_room_state_by_type( $synapse_user, $room_id );
      })->then( sub {
         my ( $state ) = @_;
         $state->{'m.room.power_levels'} and die 'power_levels_event was accepted';

         # XXX is there a better way of testing that the PL event was rejected?
         Future->done(1);
     });
  };
