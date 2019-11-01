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

push our @EXPORT, qw ( upgrade_room_synced $TEST_NEW_VERSION );

my $TEST_NEW_VERSION = '2';

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

=head2 is_direct_room

    is_direct_room( $user, $room_id )->then( sub {
        my ( $is_direct ) = @_;
    })

Check if a room is considered to be a direct chat by the given user.

=cut

sub is_direct_room {
   my ( $user, $room_id ) = @_;

   # Download account data events from sync
   matrix_get_account_data( $user, "m.direct" )->then( sub {
      # Should only have the m.direct event in account_data
      my ( $data ) = @_;

      log_if_fail "m.direct account data", $data;

      # Check if the room_id is in the list of direct rooms
      foreach my $user_id ( keys %{ $data } ) {
         my $room_ids = $data->{$user_id};

         # Return whether the given room ID is in the response
         foreach my $room (@$room_ids) {
            if ( $room eq $room_id ) {
               return Future->done( 1 );
            }
         }
      }

      # Didn't find a direct room with our room ID
      Future->done( 0 );
   });
}

=head2 upgrade_room_synced

    upgrade_room_synced( $user, $room_id, %opts )->then( sub {
        my ( $new_room_id ) = @_;
    })

Request that the homeserver upgrades the given room, and waits for the
new room to appear in the sync result.

%opts may include:

=over

=item expected_event_counts => HASH

The number of events of each type we expect to appear in the new room. A map
from event type to count.

=back

Other %opts are as for C<upgrade_room>.

=cut

sub upgrade_room_synced {
   my ( $user, $room_id, %opts ) = @_;

   my $expected_event_counts = delete $opts{expected_event_counts} // {};
   foreach my $t (qw(
      m.room.create m.room.member m.room.guest_access
      m.room.history_visibility m.room.join_rules m.room.power_levels
   )) {
      $expected_event_counts->{$t} //= 1;
   }

   # map from event type to count
   my %received_event_counts = map { $_ => 0 } keys %$expected_event_counts;

   matrix_do_and_wait_for_sync(
      $user,
      do => sub {
         upgrade_room( $user, $room_id, %opts );
      },
      check => sub {
         my ( $sync_body, $new_room_id ) = @_;
         return 0 if not exists $sync_body->{rooms}{join}{$new_room_id};
         my $tl = $sync_body->{rooms}{join}{$new_room_id}{timeline}{events};
         my $st = $sync_body->{rooms}{join}{$new_room_id}{state}{events};
         log_if_fail "New room timeline", $tl;
         log_if_fail "New room state", $st;

         foreach my $ev ( @$tl ) {
            $received_event_counts{$ev->{type}} += 1;
         }
         foreach my $ev ( @$st ) {
            $received_event_counts{$ev->{type}} += 1;
         }

         # check we've got all the events we expect
         foreach my $t ( keys %$expected_event_counts ) {
            if( $received_event_counts{$t} < $expected_event_counts->{$t} ) {
               log_if_fail "Still waiting for a $t event";
               return 0;
            }
         }
         return 1;
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
      my ( $new_room_id );

      matrix_sync( $user )->then( sub {
         upgrade_room_synced(
            $user, $old_room_id,
            new_version => $TEST_NEW_VERSION,
         );
      })->then( sub {
         ( $new_room_id, ) = @_;

         matrix_sync_again( $user );
      })->then( sub {
         my ( $sync_body ) = @_;

         log_if_fail "sync body", $sync_body;

         # check the new room has the right version

         my $room = $sync_body->{rooms}{join}{$new_room_id};
         my $ev0 = $room->{timeline}{events}[0];

         assert_eq( $ev0->{type}, 'm.room.create', 'first event in new room' );
         assert_json_keys( $ev0->{content}, qw( room_version ));
         assert_eq( $ev0->{content}{room_version}, $TEST_NEW_VERSION, 'room_version' );

         # the old room should have a tombstone event
         my $old_room_timeline = $sync_body->{rooms}{join}{$old_room_id}{timeline}{events};
         my $tombstone_event = $old_room_timeline->[0];
         assert_eq(
            $tombstone_event->{type},
            'm.room.tombstone',
            'event in old room',
         );
         assert_eq(
            $tombstone_event->{content}{replacement_room},
            $new_room_id,
            'room_id in tombstone'
         );

         # the new room should link to the old room
         assert_json_keys( $ev0->{content}, qw( predecessor ));
         assert_json_keys( $ev0->{content}{predecessor}, qw( room_id event_id ));
         assert_eq( $ev0->{content}{predecessor}{room_id}, $old_room_id );
         assert_eq( $ev0->{content}{predecessor}{event_id}, $tombstone_event->{event_id} );

         Future->done(1);
      });
   };

foreach my $vis ( qw( public private ) ) {
   test "/upgrade should preserve room visibility for $vis rooms",
      requires => [
         local_user_and_room_fixtures(),
         qw( can_upgrade_room_version ),
      ],

      do => sub {
         my ( $creator, $room_id ) = @_;

         # set the visibility on the old room. (The default is 'private', but
         # we may as well set it explicitly.)
         do_request_json_for(
            $creator,
            method   => "PUT",
            uri      => "/r0/directory/list/room/$room_id",
            content  => {
               visibility => $vis,
            },
         )->then( sub {
            upgrade_room_synced(
               $creator, $room_id,
               new_version => $TEST_NEW_VERSION,
            );
         })->then( sub {
            my ( $new_room_id, ) = @_;

            # check the visibility of the new room
            do_request_json_for(
               $creator,
               method   => "GET",
               uri      => "/r0/directory/list/room/$new_room_id",
            );
         })->then( sub {
            my ( $response ) = @_;
            log_if_fail "room vis", $response;
            assert_eq(
               $response->{visibility},
               $vis,
               "replacement room visibility",
              );
            Future->done(1);
         });
      };
}

test "/upgrade copies the power levels to the new room",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_upgrade_room_version can_change_power_levels ),
   ],

   do => sub {
      my ( $creator, $room_id ) = @_;

      my ( $pl_content, $new_room_id );

      matrix_change_room_power_levels(
         $creator, $room_id, sub {
             ( $pl_content ) = @_;
             $pl_content->{users}->{'@test:xyz'} = 40;
             log_if_fail "PL content in old room", $pl_content;
         }
      )->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         upgrade_room_synced(
            $creator, $room_id,
            expected_event_counts => { 'm.room.power_levels' => 2 },
            new_version => $TEST_NEW_VERSION,
         );
      })->then( sub {
         ( $new_room_id, ) = @_;

         matrix_sync_again( $creator );
      })->then( sub {
         my ( $sync_body ) = @_;

         log_if_fail "sync body", $sync_body;

         my $room = $sync_body->{rooms}{join}{$new_room_id};
         my $pl_event = first {
            $_->{type} eq 'm.room.power_levels'
         } reverse @{ $room->{timeline}->{events} };

         log_if_fail "PL event in new room", $pl_event;

         assert_deeply_eq(
            $pl_event->{content},
            $pl_content,
            "power levels in replacement room",
         );
         Future->done(1);
      });
   };


test "/upgrade copies important state to the new room",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $creator, $room_id ) = @_;
      my ( $new_room_id );

      # map from type to content
      my %STATE_DICT = (
         "m.room.topic" => { topic => "topic" },
         "m.room.name" => { name => "name" },
         "m.room.join_rules" => { join_rule => "public" },
         "m.room.guest_access" => { guest_access => "forbidden" },
         "m.room.history_visibility" => { history_visibility => "joined" },
         "m.room.avatar" => { url => "http://something" },
         "m.room.encryption" => { algorithm => "m.megolm.v1.aes-sha2" },
         "m.room.related_groups" => { groups => [ "+something:example.org" ] },
         "m.room.server_acl" => {
            allow => [ "*" ],
            allow_ip_literals => "false",
            deny => [ "*.evil.com", "evil.com" ],
         },
      );

      my $f = Future->done(1);
      foreach my $k ( keys %STATE_DICT ) {
         $f = $f->then( sub {
            matrix_put_room_state(
               $creator, $room_id,
               type => $k,
               content => $STATE_DICT{$k},
            );
         });
      }

      $f->then( sub {
         # to make things harder, we now restrict our ability to change each of
         # those states: the server should make sure it sets up the state
         # *before* it replicates the PL.
         matrix_change_room_power_levels(
            $creator, $room_id, sub {
               my ( $levels ) = @_;
               foreach my $k ( keys %STATE_DICT ) {
                  $levels->{events}->{$k} = 80;
               }
               $levels->{users}->{$creator->user_id} = 50;
            },
         );
      })->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         upgrade_room_synced(
            $creator, $room_id,
            new_version => $TEST_NEW_VERSION,
         );
      })->then( sub {
         ( $new_room_id, ) = @_;

         matrix_sync_again( $creator );
      })->then( sub {
         my ( $sync_body ) = @_;

         log_if_fail "sync body", $sync_body;

         my $room = $sync_body->{rooms}{join}{$new_room_id};

         foreach my $k ( keys %STATE_DICT ) {
            my $event = first {
               $_->{type} eq $k && $_->{state_key} eq '',
            } @{ $room->{timeline}->{events} };

            log_if_fail "State for $k", $event->{content};
            assert_deeply_eq(
               $event->{content},
               $STATE_DICT{$k},
               "$k in replacement room",
            );
         }
         Future->done(1);
      });
   };


test "/upgrade copies ban events to the new room",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $creator, $room_id ) = @_;
      my ( $new_room_id );

      my $content = {
         membership => "ban",
      };

      matrix_put_room_state(
         $creator, $room_id,
         type => "m.room.member",
         content => $content,
         state_key => '@bob:matrix.org',
      )->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         upgrade_room_synced(
            $creator, $room_id,
            new_version => $TEST_NEW_VERSION,
         );
      })->then( sub {
         ( $new_room_id, ) = @_;

         await_sync_timeline_or_state_contains( $creator, $new_room_id, check => sub {
            my ( $event ) = @_;

            return unless $event->{type} eq "m.room.member";
            return unless $event->{state_key} eq "\@bob:matrix.org";

            assert_deeply_eq(
               $event->{content},
               $content,
               "no ban in replacement room",
            );

            return 1;
         });
      });
   };

test "/upgrade copies push rules to the new room",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $creator, $room_id ) = @_;
      my ( $new_room_id );

      matrix_add_push_rule( $creator, "global", "room", $room_id, {
         actions => [ "notify" ]
      })->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         upgrade_room_synced(
            $creator, $room_id,
            new_version => $TEST_NEW_VERSION,
         );
      })->then( sub {
         ( $new_room_id, ) = @_;

         matrix_get_push_rules( $creator )->then( sub {
            my ( $body ) = @_;

            my @to_check;

            foreach my $kind ( keys %{ $body->{global} } ) {
               foreach my $rule ( @{ $body->{global}{$kind} } ) {
                  push @to_check, [ $kind, $rule->{rule_id} ];
               }
            }

            my $found = 0;
            try_repeat {
               my $to_check = shift;

               my ( $kind, $rule_id ) = @$to_check;

               log_if_fail("testing $rule_id against $new_room_id");

               if ( $rule_id eq $new_room_id ) {
                  $found = 1;
               }
            } foreach => \@to_check;

            if ( $found == 1 ) {
               Future->done(1);
            }
         })
      });
   };

test "/upgrade moves aliases to the new room",
   requires => [
      $main::HOMESERVER_INFO[0],
      local_user_and_room_fixtures(),
      room_alias_fixture(),
      room_alias_fixture(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $info, $creator, $room_id, $room_alias_1, $room_alias_2 ) = @_;

      my $server_name = $info->server_name;
      my $new_room_id;

      do_request_json_for(
         $creator,
         method => "PUT",
         uri    => "/r0/directory/room/$room_alias_1",
         content => { room_id => $room_id },
      )->then( sub {
         do_request_json_for(
            $creator,
            method => "PUT",
            uri    => "/r0/directory/room/$room_alias_2",
            content => { room_id => $room_id },
         );
      })->then( sub {
         # alias 1 is the canonical alias.
         matrix_put_room_state( $creator, $room_id,
            type    => "m.room.canonical_alias",
            content => {
               alias => $room_alias_1,
            },
         );
      })->then( sub {
         upgrade_room_synced(
            $creator, $room_id,
            new_version => $TEST_NEW_VERSION,
            expected_event_counts => {
               'm.room.aliases' => 1, 'm.room.canonical_alias' => 1,
            },
         );
      })->then( sub {
         ( $new_room_id ) = @_;

         matrix_get_room_state(
            $creator, $room_id,
            type=>'m.room.aliases', state_key=>$server_name,
         );
      })->then( sub {
         my ( $old_aliases ) = @_;
         assert_deeply_eq( $old_aliases, {aliases => []}, "aliases on old room" );

         matrix_get_room_state( $creator, $room_id, type=>'m.room.canonical_alias' );
      })->then( sub {
         my ( $old_canonical_alias ) = @_;
         assert_deeply_eq(
            $old_canonical_alias, {}, "canonical_alias on old room",
         );

         matrix_get_room_state(
            $creator, $new_room_id,
            type=>'m.room.aliases', state_key=>$server_name,
         );
      })->then( sub {
         my ( $new_aliases ) = @_;
         assert_deeply_eq(
            [ sort( @{ $new_aliases->{aliases} } ) ],
            [ sort( $room_alias_1, $room_alias_2 ) ],
            "aliases on new room",
         );

         matrix_get_room_state(
            $creator, $new_room_id, type=>'m.room.canonical_alias',
         );
      })->then( sub {
         my ( $new_canonical_alias ) = @_;
         assert_deeply_eq(
            $new_canonical_alias,
            { alias => $room_alias_1 },
            "canonical_alias on new room",
         );

         # check that the directory now maps the aliases to the new room
         do_request_json_for(
            $creator,
            method => "GET",
            uri    => "/r0/directory/room/$room_alias_1",
         )->then( sub {
            my ( $body ) = @_;

            assert_eq( $body->{room_id}, $new_room_id, "room_id for alias 1" );

            do_request_json_for(
               $creator,
               method => "GET",
               uri    => "/r0/directory/room/$room_alias_2",
            );
         })->then( sub {
            my ( $body ) = @_;

            assert_eq( $body->{room_id}, $new_room_id, "room_id for alias 2" );

            Future->done(1);
         });
      });
   };

test "/upgrade preserves direct room state",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $creator, $room_id ) = @_;

      my $new_room_id;
      my $user_id = $creator->user_id;

      do_request_json_for(
         $creator,
         method => "PUT",
         uri    => "/r0/user/$user_id/account_data/m.direct",
         content => { $user_id => [$room_id] },
      )->then( sub {
         upgrade_room_synced(
            $creator, $room_id,
            new_version => $TEST_NEW_VERSION,
         );
      })->then( sub {
         ( $new_room_id ) = @_;

         is_direct_room( $creator, $new_room_id );
      })->then( sub {
         my ( $is_direct_room ) = @_;

         $is_direct_room == 1 or die "Expected upgraded room to be a direct room";
         Future->done( 1 );
      });
   };

test "/upgrade preserves room federation ability",
   requires => [
      local_user_fixture(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $creator ) = @_;

      do_request_json_for( $creator,
         method => "POST",
         uri    => "/r0/createRoom",

         content => {
            creation_content => {
               "m.federate" => JSON::false,
            },
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));
         assert_json_nonempty_string( my $old_room_id = $body->{room_id} );

         upgrade_room_synced(
            $creator, $old_room_id,
            new_version => $TEST_NEW_VERSION,
         );
      })->then( sub {
         ( my $new_room_id, ) = @_;

         do_request_json_for( $creator,
            method => "GET",
            uri    => "/r0/rooms/$new_room_id/state/m.room.create",
         )
      })->then( sub {
         my ( $state ) = @_;

         log_if_fail "upgraded room state", $state;

         assert_json_keys( $state, qw( m.federate ));

         Future->done(1);
      });
   };

test "/upgrade restricts power levels in the old room",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $creator, $room_id ) = @_;

      log_if_fail "Old room id", $room_id;

      upgrade_room_synced(
         $creator, $room_id,
         new_version => $TEST_NEW_VERSION,
      )->then( sub {
         my ( $new_room_id ) = @_;

         matrix_get_room_state(
            $creator, $room_id, type=>'m.room.power_levels',
         );
      })->then( sub {
         my ( $pl_event ) = @_;

         log_if_fail 'power_levels after upgrade', $pl_event;
         assert_eq( $pl_event->{events_default}, 50, "events_default" );
         assert_eq( $pl_event->{invite}, 50, "invite" );
         Future->done(1);
      });
   };

test "/upgrade restricts power levels in the old room when the old PLs are unusual",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $creator, $room_id ) = @_;

      matrix_change_room_power_levels(
         $creator, $room_id, sub {
            my ( $levels ) = @_;
            $levels -> {users_default} = 80;
         }
      )->then( sub {
         upgrade_room_synced(
            $creator, $room_id,
            expected_event_counts => { 'm.room.power_levels' => 2 },
            new_version => $TEST_NEW_VERSION,
         );
      })->then( sub {
         my ( $new_room_id ) = @_;

         matrix_get_room_state(
            $creator, $room_id, type=>'m.room.power_levels',
         );
      })->then( sub {
         my ( $pl_event ) = @_;

         log_if_fail 'power_levels after upgrade', $pl_event;

         assert_eq( $pl_event->{events_default}, 81, "events_default" );
         assert_eq( $pl_event->{invite}, 81, "invite" );
         Future->done(1);
      });
   };

test "/upgrade to an unknown version is rejected",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $user, $room_id ) = @_;

      upgrade_room(
         $user, $room_id,
         new_version => 'my_bad_version',
      )->main::expect_matrix_error( 400, 'M_UNSUPPORTED_ROOM_VERSION' );
   };

test "/upgrade is rejected if the user can't send state events",
   requires => [
      local_user_and_room_fixtures(),
      local_user_fixture(),
      qw( can_create_versioned_room ),
   ],

   do => sub {
      my ( $creator, $room_id, $joiner ) = @_;
      my ( $replacement_room );

      matrix_join_room( $joiner, $room_id )->then( sub {
         upgrade_room(
            $joiner, $room_id,
         )->main::expect_matrix_error( 403, 'M_FORBIDDEN' );
      });
   };

test "/upgrade of a bogus room fails gracefully",
   requires => [
      local_user_fixture(),
   ],

   do => sub {
      my ( $user ) = @_;
      my ( $replacement_room );

      upgrade_room(
         $user, "!fail:unknown",
      )->main::expect_matrix_error( 404, 'M_NOT_FOUND' );
   };

test "Cannot send tombstone event that points to the same room",
   requires => [
      local_user_and_room_fixtures(),
      qw( can_upgrade_room_version can_change_power_levels ),
   ],

   do => sub {
      my ( $creator, $room_id ) = @_;

      matrix_send_room_message( $creator, $room_id,
         type    => "m.room.tombstone",
         content => {
            replacement_room => $room_id,
         }
      )->main::expect_http_400;
   };

test "Local and remote users' homeservers remove a room from their public directory on upgrade",
   requires => [
      local_user_fixture(), remote_user_fixture(),
      qw( can_upgrade_room_version ),
   ],

   do => sub {
      my ( $creator, $remote_joiner ) = @_;
      my ( $room_id, $new_room_id, $pl_event_id );

      matrix_create_room( $creator,
         visibility => "public",
      )->then( sub {
         ( $room_id, ) = @_;

         matrix_invite_user_to_room_synced(
            $creator, $remote_joiner, $room_id,
         );
      })->then( sub {
         matrix_join_room_synced(
            $remote_joiner, $room_id, ( server_name => $creator->server_name, ),
         );
      })->then( sub {
         matrix_change_room_power_levels( $creator, $room_id, sub {
            my ( $levels ) = @_;
            $levels->{users}{$remote_joiner->user_id} = 100;
         });
      })->then(sub {
         ( $pl_event_id, ) = @_;

         # Extract event_id from response object
         $pl_event_id = $pl_event_id->{event_id};

         # Wait for the power level change to appear on the remote side
         await_sync_timeline_contains( $remote_joiner, $room_id, check => sub {
            say "We want: " . $pl_event_id . ", we got: " . $_[0]->{type};
            return $_[0]->{event_id} eq $pl_event_id;
         });
      })->then(sub {
         do_request_json_for( $remote_joiner,
            method => "PUT",
            uri    => "/r0/directory/list/room/$room_id",

            content => {
               visibility => "public",
            }
         )
      })->then(sub {
         upgrade_room_synced(
            $creator, $room_id,
            new_version => $main::TEST_NEW_VERSION,
         );
      })->then(sub {
         ( $new_room_id ) = @_;

         matrix_join_room_synced(
            $remote_joiner, $new_room_id, ( server_name => $creator->server_name, )
         );
      })->then(sub {
         do_request_json_for( $creator,
            method => "GET",
            uri    => "/r0/publicRooms",
         );
      })->then( sub {
         # Check public rooms list for local user
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( chunk ) );

         # Check that the room list contains new room id
         any { $new_room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Local room list did not include expected room id $new_room_id";

         # Check that the room list doesn't contain old room id
         none { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Local room list included unexpected room id $room_id";

         do_request_json_for( $remote_joiner,
            method => "GET",
            uri    => "/r0/publicRooms",
         );
      })->then( sub {
         # Check public rooms list for remote user
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( chunk ) );

         # Check that the room list contains new room id
         any { $new_room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Remote room list did not include expected room id $new_room_id";

         # Check that the room list doesn't contain old room id
         none { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Remote room list included unexpected room id $room_id";

         Future->done( 1 );
      });
   }
