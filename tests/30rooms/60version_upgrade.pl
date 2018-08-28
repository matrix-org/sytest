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

# TODO: switch this to '2' once that is released
my $TEST_NEW_VERSION = 'vdh-test-version';

=head2 upgrade_room

    upgrade_room( $user, $room_id, %opts )->then( sub {
        my ( $new_room_id ) = @_;
    })

Request that the homeserver upgrades the given room.

%opts may include:

=over

=item new_version => STRING

Defaults to $TEST_NEW_VERSION if unspecified

=back

=cut

sub upgrade_room {
   my ( $user, $room_id, %opts ) = @_;

   my $new_version = $opts{new_version} // $TEST_NEW_VERSION;

   do_request_json_for(
      $user,
      method  => "POST",
      uri     => "/r0/rooms/$room_id/upgrade",
      content => {
         new_version => $new_version,
      },
   )->then( sub {
      my ( $body ) = @_;
      log_if_fail "upgrade response", $body;

      assert_json_keys( $body, qw( replacement_room ) );
      Future->done( $body->{replacement_room} );
   });
}

=head2 upgrade_room_synced

    upgrade_room_synced( $user, $room_id, %opts )->then( sub {
        my ( $new_room_id, $sync_body ) = @_;
    })

Request that the homeserver upgrades the given room, and waits for the
new room to appear in the sync result.

%opts are as for C<upgrade_room>.

=cut

sub upgrade_room_synced {
   my ( $user, $room_id, %opts ) = @_;

   matrix_do_and_wait_for_sync(
      $user,
      do => sub {
         upgrade_room( $user, $room_id, %opts );
      },
      check => sub {
         my ( $sync_body, $new_room_id ) = @_;
         return 0 if not exists $sync_body->{rooms}{join}{$new_room_id};
         return $sync_body;
      },
   );
}

test "/upgrade creates a new room",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_create_versioned_room ),
   ],

   proves => [ qw( can_upgrade_room_version ) ],

   do => sub {
      my ( $user, $old_room_id ) = @_;
      my ( $replacement_room );

      upgrade_room_synced(
         $user, $old_room_id,
         new_version => $TEST_NEW_VERSION,
      )->then( sub {
         my ( $new_room_id, $sync_body ) = @_;

         log_if_fail "sync body", $sync_body;

         # check the new room has the right version

         my $room = $sync_body->{rooms}{join}{$new_room_id};
         my $ev0 = $room->{timeline}{events}[0];

         assert_eq( $ev0->{type}, 'm.room.create', 'first event in new room' );
         assert_json_keys( $ev0->{content}, qw( room_version ));
         assert_eq( $ev0->{content}{room_version}, $TEST_NEW_VERSION, 'room_version' );

         # the old room should have a tombstone event
         my $old_room_timeline = $sync_body->{rooms}{join}{$old_room_id}{timeline}{events};
         assert_eq( $old_room_timeline->[0]{type},
                    'm.room.tombstone',
                    'event in old room' );

         assert_eq(
            $old_room_timeline->[0]{content}{replacement_room},
            $new_room_id,
            'room_id in tombstone'
         );

         Future->done(1);
      });
   };

test "/upgrade to an unknown version is rejected",
   requires => [
      local_user_and_room_fixtures(),
      local_user_fixture(),
      qw( can_create_versioned_room can_upgrade_room_version),
   ],

   do => sub {
      my ( $user, $room_id ) = @_;

      upgrade_room(
         $user, $room_id,
         new_version => 'my_bad_version',
      )->main::expect_matrix_error( 'M_UNSUPPORTED_ROOM_VERSION' );
   };

test "/upgrade is rejected if the user can't send state events",
   requires => [
      local_user_and_room_fixtures(),
      local_user_fixture(),
      qw( can_create_versioned_room can_upgrade_room_version),
   ],

   do => sub {
      my ( $creator, $room_id, $joiner ) = @_;
      my ( $replacement_room );

      matrix_join_room( $joiner, $room_id )->then( sub {
         upgrade_room(
            $joiner, $room_id,
         )->main::expect_matrix_error( 'M_FORBIDDEN', http_code => 403 );
      });
   };


# upgrade without perms
# upgrade with other local users
# upgrade with remote users
# check names and aliases are copied


