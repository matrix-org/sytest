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

use Future::Utils qw( repeat );
use List::Util qw( all first none );

test "Room is transitioned on local and remote groups upon room upgrade",
   deprecated_endpoints => 1,
   requires => [
      local_admin_fixture(),
      remote_admin_fixture(),
      qw( can_upgrade_room_version )
   ],

   do => sub {
      my ( $local_user, $remote_user ) = @_;
      my ( $room_id, $new_room_id, $local_group_id, $remote_group_id );

      # Create a to-be-upgraded room
      matrix_create_room_synced(
         $local_user,
      )->then( sub {
         ( $room_id, ) = @_;

         matrix_invite_user_to_room_synced(
            $local_user, $remote_user, $room_id
         );
      })->then( sub {
         matrix_join_room_synced(
            $remote_user, $room_id, ( server_name => $local_user->server_name, )
         );
      })->then( sub {
         # Create groups
         matrix_create_group(
            $local_user, name => "Local Test Group"
         );
      })->then( sub {
         ( $local_group_id, ) = @_;

         matrix_create_group(
            $remote_user, name => "Remote Test Group",
         );
      })->then( sub {
         ( $remote_group_id, ) = @_;

         # Add the to-be-upgraded room to groups
         matrix_add_group_rooms(
            $local_user, $local_group_id, $room_id
         );
      })->then( sub {
         matrix_add_group_rooms( $remote_user, $remote_group_id, $room_id );
      })->then( sub {
         # Upgrade the room
         upgrade_room_synced(
            $local_user, $room_id,
            new_version => $main::TEST_NEW_VERSION,
         );
      })->then( sub {
         ( $new_room_id, ) = @_;

         matrix_invite_user_to_room_synced(
            $local_user, $remote_user, $new_room_id
         );
      })->then( sub {
         matrix_join_room_synced(
            $remote_user, $new_room_id, ( server_name => $local_user->server_name, )
         );
      })->then( sub{
         # Check whether the old and new room exist on each group
         matrix_get_group_rooms( $local_user, $local_group_id );
      })->then( sub {
         my ( $body, ) = @_;

         log_if_fail "Old room ID: $room_id, New room ID: $new_room_id";
         log_if_fail "Rooms on local group", $body;

         assert_json_keys( $body, qw( chunk ) );
         any { $_->{room_id} eq $new_room_id } @{ $body->{chunk} }
            or die "Upgraded room not in local group rooms list";

         none { $_->{room_id} eq $room_id } @{ $body->{chunk} }
            or die "Old room still present in local group rooms list";

         matrix_get_group_rooms( $remote_user, $remote_group_id );
      })->then( sub {
         my ( $body, ) = @_;

         log_if_fail "Old room ID: $room_id, New room ID: $new_room_id";
         log_if_fail "Rooms on remote group", $body;

         assert_json_keys( $body, qw( chunk ) );
         any { $_->{room_id} eq $new_room_id } @{ $body->{chunk} }
            or die "Upgraded room not in remote group rooms list";

         none { $_->{room_id} eq $room_id } @{ $body->{chunk} }
            or die "Old room still present in remote group rooms list";

         Future->done( 1 );
      });
   };
