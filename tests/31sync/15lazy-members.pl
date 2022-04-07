use Future::Utils qw( repeat );

# returns a sub suitable for passing to `await_sync_timeline_contains` which checks if
# the event is a filler event from the given sender with the given number.
sub check_filler_event {
   my ( $expected_sender, $expected_filler_number ) = @_;

   return sub {
      my ($event) = @_;
      log_if_fail "check_filler_event: event", $event;
      return $event->{type} eq "a.made.up.filler.type" &&
         $event->{sender} eq $expected_sender &&
         $event->{content}->{filler} == $expected_filler_number;
   }
}

test "Lazy loading parameters in the filter are strictly boolean",
   requires => [ local_user_fixtures( 1 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice ) = @_;

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => "true",
            },
         }
      })->main::expect_http_400()
      ->then( sub {
         matrix_create_filter( $alice, {
            room => {
               state => {
                  lazy_load_members => 1,
               },
            }
         })->main::expect_http_400()
      })->then( sub {
         matrix_create_filter( $alice, {
            room => {
               state => {
                  include_redundant_members => "true",
               },
            }
         })->main::expect_http_400()
      })->then( sub {
         matrix_create_filter( $alice, {
            room => {
               state => {
                  include_redundant_members => 1,
               },
            }
         })->main::expect_http_400()
      })->then( sub {
         Future->done(1);
      });
   };

test "The only membership state included in an initial sync is for all the senders in the timeline",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Charlie sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # She should only see Charlie in the membership list (and herself)

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         matrix_send_filler_messages_synced( $charlie, $room_id, 10 );
      })->then( sub {
         # Ensure synapse has propagated this message to Alice's sync stream
         await_sync_timeline_contains( $alice, $room_id, check => check_filler_event( $charlie->user_id, 10 ));
      })->then( sub {
         defined( $alice->sync_next_batch ) and die "Alice should not have a next batch token set";
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "alice's initial sync returned", $body->{rooms}->{join}->{$room_id}->{timeline};
         assert_room_members ( $body, $room_id, [ $alice->user_id, $charlie->user_id ]);
         Future->done(1);
      });
   };


test "The only membership state included in an incremental sync is for senders in the timeline",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # Alice should see only Bob in the membership list (and herself).
      # Charlie sends an event
      # Alice syncs again; she should only see Charlie's membership event
      # in the incremental sync as Charlie sent anything in this timeframe.

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         my $state = $body->{rooms}{join}{$room_id}{state}{events};

         assert_state_types_match( $state, $room_id, [
            [ 'm.room.create', '' ],
            [ 'm.room.join_rules', '' ],
            [ 'm.room.power_levels', '' ],
            [ 'm.room.name', '' ],
            [ 'm.room.history_visibility', '' ],
            [ 'm.room.member', $alice->user_id ],
            [ 'm.room.member', $bob->user_id ],
         ]);

         matrix_send_room_text_message_synced( $charlie, $room_id,
            body => "Message from charlie",
         )
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         my $state = $body->{rooms}{join}{$room_id}{state}{events};

         assert_state_types_match( $state, $room_id, [
            [ 'm.room.member', $charlie->user_id ],
         ]);

         # check syncing again doesn't return any state changes
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         if( exists $body->{rooms} and exists $body->{rooms}{join} ) {
            my $joined_rooms = $body->{rooms}{join};
            assert_deeply_eq($joined_rooms, {});
         }
         Future->done(1);
      });
   };


# XXX: N.B. THIS TEST IS DISABLED ATM AS WE HAVE DISABLED LL IN GAPPY SYNCS
test "The only membership state included in a gapped incremental sync is for senders in the timeline",
   requires => [ local_user_fixtures( 4 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie, $dave ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # Alice should see only Bob in the membership list (and herself).
      # Dave joins
      # Dave sends 10 events
      # Charlie then sends 10 events
      # Alice syncs again; she should get a gappy sync and only see
      # Dave's membership event as she never received Charlie's timeline events.
      # XXX: THIS SHOULD FAIL, as LL is disabled for incremental syncs.

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $alice->user_id, $bob->user_id ]);

         matrix_join_room( $dave, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $dave, $room_id, 10 );
      })->then( sub {
         matrix_send_filler_messages_synced( $charlie, $room_id, 10 );
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_room_members( $body, $room_id, [ $dave->user_id ]);
         Future->done(1);
      });
   };


test "Gapped incremental syncs include all state changes",
   # sending 50 messages can take a while
   timeout => 20,

   requires => [ local_user_fixtures( 4 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie, $dave ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # Alice should see only Bob in the membership list (and herself).
      # Dave joins
      # Charlie then sends 20 events to trigger a gappy sync.
      # Alice syncs again; she should get a gappy sync and see both
      #   Charlie and Dave, even though Dave hasn't said anything yet.
      # Dave then leaves
      # Charlie then sends 20 events to trigger a gappy sync.
      # Alice syncs again; she should get a gappy sync and see
      #   only Dave's parted membership event in state.

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room_synced( $bob, $room_id );
      })->then( sub {
         matrix_join_room_synced( $charlie, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         log_if_fail "Bob successfully sent first batch of 10 filler messages, checking Alice can see them...";
         await_sync_timeline_contains( $alice, $room_id, check => check_filler_event( $bob->user_id, 10 ));
      })->then( sub {
         log_if_fail "Alice's first sync...";
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $alice->user_id, $bob->user_id ]);
         log_if_fail "Alice's first sync is good. Dave joins the room...";
         matrix_join_room_synced( $dave, $room_id );
      })->then( sub {
         log_if_fail "Charlie sends a load of messages...";
         matrix_send_filler_messages_synced( $charlie, $room_id, 20 );
      })->then( sub {
         log_if_fail "Charlie sent filler messages, checking Alice can see them...";
         await_sync_timeline_contains( $alice, $room_id, check => check_filler_event( $charlie->user_id, 20 ));
      })->then( sub {
         log_if_fail "Alice's second sync...";
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $charlie->user_id, $dave->user_id ]);
         log_if_fail "Alice's second sync is good. Dave leaves the room...";
         matrix_leave_room_synced( $dave, $room_id );
      })->then( sub {
         log_if_fail "Charlie sends another load of messages...";
         matrix_send_filler_messages_synced( $charlie, $room_id, 20 );
      })->then( sub {
         log_if_fail "Charlie sent filler messages, checking Alice can see them...";
         await_sync_timeline_contains( $alice, $room_id, check => check_filler_event( $charlie->user_id, 20 ));
      })->then( sub {
         log_if_fail "Alice's third sync...";
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         my $state = $body->{rooms}{join}{$room_id}{state}{events};
         assert_state_room_members_match( $state, { $dave->user_id => 'leave' });

         Future->done(1);
      });
   };


test "Old leaves are present in gapped incremental syncs",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Charlie sends 1 event into it
      # Bob sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # Alice should see only Bob in the membership list (and herself).
      # Charlie leaves
      # Bob sends another 10 events (for gappy sync)
      # Alice syncs and should see gappy sync; should see only Charlie having left.

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room_synced( $bob, $room_id );
      })->then( sub {
         matrix_join_room_synced( $charlie, $room_id );
      })->then( sub {
         matrix_send_room_text_message_synced( $charlie, $room_id,
            body => "Hello world",
         )
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         log_if_fail "Bob successfully sent first batch of 10 filler messages, checking Alice can see them";
         await_sync_timeline_contains( $alice, $room_id, check => check_filler_event( $bob->user_id, 10 ));
      })->then( sub {
         log_if_fail "Doing Alice's first full sync";
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $alice->user_id, $bob->user_id ]);
         log_if_fail "Alice's first sync is good. Charlie leaves...";
         matrix_leave_room_synced( $charlie, $room_id );
      })->then( sub {
         log_if_fail "Bob sends more messages...";
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         log_if_fail "Bob successfully sent second batch of 10 filler messages, checking Alice can see them";
         await_sync_timeline_contains( $alice, $room_id, check => check_filler_event( $bob->user_id, 10 ));
      })->then( sub {
         log_if_fail "Syncing again from Alice";
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         my $state = $body->{rooms}{join}{$room_id}{state}{events};
         assert_state_room_members_match( $state, { $charlie->user_id => 'leave' });

         Future->done(1);
      });
   };


test "Leaves are present in non-gapped incremental syncs",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Charlie sends 1 event into it
      # Bob sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # Alice should see only Bob in the membership list (and herself).
      # Charlie leaves
      # Bob sends 5 events (no gappy sync)
      # Alice syncs and should see non-gappy sync; should see only Charlie having left.

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room_synced( $bob, $room_id );
      })->then( sub {
         matrix_join_room_synced( $charlie, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $charlie, $room_id,
            body => "Hello world",
         )
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         # Ensure server has propagated those messages to Alice's sync stream
         await_sync_timeline_contains( $alice, $room_id, check => check_filler_event( $bob->user_id, 10 ));
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $alice->user_id, $bob->user_id ]);

         matrix_leave_room_synced( $charlie, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 5 );
      })->then( sub {
         await_sync_timeline_contains( $alice, $room_id, check => check_filler_event( $bob->user_id, 5 ));
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         # XXX: i'm surprised we have an explicit state entry here at all,
         # given the state transition is included in the timeline.
         my $state = $body->{rooms}{join}{$room_id}{state}{events};
         assert_state_room_members_match( $state, { $charlie->user_id => 'leave' });

         Future->done(1);
      });
   };

test "Old members are included in gappy incr LL sync if they start speaking",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Alice initial syncs with a filter on the last 10 events, and LL members
      # Alice should see only Bob in the membership list (and herself)
      # Bob then sends another 10 events (to trigger a gappy sync)
      # Charlie then sends 10 events (as an old user coming back to life)
      # Alice syncs again; she should get a gappy sync and see
      # Charlie's membership (due to his timeline events).

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $alice->user_id,
            $bob->user_id,
         ]);

         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         matrix_send_filler_messages_synced( $charlie, $room_id, 10 );
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $charlie->user_id,
         ]);
         Future->done(1);
      });
   };


test "Members from the gap are included in gappy incr LL sync",
   requires => [ local_user_fixtures( 4 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie, $dave ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Alice initial syncs with a filter on the last 10 events, and LL members
      # Alice should see only Bob in the membership list (and herself)
      # Dave joins
      # Charlie then sends 10 events
      # Alice syncs again; she should get a gappy sync and see both
      # Charlie's membership (due to his timeline events) and
      # Dave's membership (because he joined during the gap)

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $alice->user_id,
            $bob->user_id,
         ]);

         matrix_join_room( $dave, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $charlie, $room_id, 10 );
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $charlie->user_id,
            $dave->user_id
         ]);
         Future->done(1);
      });
   };


test "We don't send redundant membership state across incremental syncs by default",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join
      # Bob sends 10 events into it
      # Charlie sends 5 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # Alice should see only Bob and Charlie in the membership list (and herself).
      # Bob sends 1 more event
      # Charlie sends 1 more event
      # Alice syncs again; she should not see any membership events as
      # the redundant ones for Bob and Charlie are removed

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         matrix_send_filler_messages_synced( $charlie, $room_id, 5 );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $alice->user_id,
            $bob->user_id,
            $charlie->user_id
         ]);

         matrix_send_room_text_message_synced( $bob, $room_id,
            body => "New message from bob",
         )
      })->then( sub {
         matrix_send_room_text_message_synced( $charlie, $room_id,
            body => "New message from charlie",
         )
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, []);
         Future->done(1);
      });
   };


test "We do send redundant membership state across incremental syncs if asked",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join
      # Bob sends 10 events into it
      # Charlie sends 5 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      #   and include_redundant_members
      # Alice should see only Bob and Charlie in the membership list (and herself)
      # Bob sends 1 more event
      # Charlie sends 1 more event
      # Alice syncs again; she should see redundant membership events for Bob and
      # Charlie again.  We don't include herself as redundant.

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true,
               include_redundant_members => JSON::true,
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $bob, $room_id, 10 );
      })->then( sub {
         matrix_send_filler_messages_synced( $charlie, $room_id, 5 );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $alice->user_id,
            $bob->user_id,
            $charlie->user_id
         ]);

         matrix_send_room_text_message( $bob, $room_id,
            body => "New message from bob",
         )
      })->then( sub {
         matrix_send_room_text_message_synced( $charlie, $room_id,
            body => "New message from charlie",
         )
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $bob->user_id,
            $charlie->user_id
         ]);
         Future->done(1);
      });
   };


test "Rejecing invite over federation doesn't break incremental /sync",
   requires => [ remote_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],

   check => sub {
      my ( $invitee, $creator, $room_id ) = @_;

      my ( $filter_id );

      matrix_create_filter( $invitee, {
         room => {
            state => {
               lazy_load_members => JSON::true,
               include_redundant_members => JSON::true,
            },
            timeline => {
               limit => 10
            },
         }
      })->then( sub {
         ( $filter_id ) = @_;

         matrix_sync( $invitee, filter => $filter_id )
      })->then( sub {
         matrix_invite_user_to_room_synced( $creator, $invitee, $room_id )
      })->then( sub {
         matrix_leave_room_synced( $invitee, $room_id )
      })->then( sub {
         matrix_sync_again( $invitee, filter => $filter_id )
      })->then( sub {
         my ( $body ) = @_;

         # Check that invitee no longer sees the invite

         if( exists $body->{rooms} and exists $body->{rooms}{invite} ) {
            assert_json_object( $body->{rooms}{invite} );
            keys %{ $body->{rooms}{invite} } and die "Expected empty dictionary";
         }

         Future->done( 1 );
      });
   };
