use Future::Utils qw( repeat );

test "State is included in the timeline in the initial sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [ "a.madeup.test.state" ] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => {types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state_synced( $user, $room_id,
            type    => "a.madeup.test.state",
            content => { "my_key" => 1 },
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));

         # state from the timeline should *not* appear in the state dictionary
         assert_json_empty_list( $room->{state}{events} );

         @{ $room->{timeline}{events} } == 1
            or die "Expected one timeline event";

         my $event = $room->{timeline}{events}[0];
         $event->{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $event->{content}{my_key} == 1
            or die "Unexpected event content";

         Future->done(1);
      })
   };

# state that has arrived over federation counts as an 'outlier', so should
# only appear in the state dictionary, not the timeline.
test "State from remote users is included in the state in the initial sync",
    requires => [ local_user_fixture( with_events => 0 ), remote_user_fixture(),
                  qw( can_sync ) ],

    check => sub {
        my ( $user, $remote_user) = @_;

        my ( $filter_id, $room_id );

        my $filter = {
            room => {
                timeline  => { types => [ "a.madeup.test.state" ] },
                state     => { types => [ "a.madeup.test.state" ] },
                ephemeral => { types => [] },
            },
            presence => {types => [] },
        };

        matrix_create_filter( $user, $filter )->then( sub {
            ( $filter_id ) = @_;

            matrix_create_room( $remote_user );
        })->then( sub {
            ( $room_id ) = @_;

            matrix_put_room_state( $remote_user, $room_id,
                                   type    => "a.madeup.test.state",
                                   content => { "my_key" => 1 });
        })->then( sub {
            matrix_invite_user_to_room_synced(
               $remote_user, $user, $room_id
            );
        })->then( sub {
            matrix_join_room_synced( $user, $room_id );
        })->then( sub {
            matrix_sync( $user, filter => $filter_id );
        })->then( sub {
            my ( $body ) = @_;

            my $room = $body->{rooms}{join}{$room_id};
            assert_json_keys( $room, qw( timeline state ephemeral ));

            @{ $room->{state}{events} } == 1
                or die "Expected one state event";

            assert_json_empty_list( $room->{timeline}{events} );

            my $event = $room->{state}{events}[0];
            $event->{type} eq "a.madeup.test.state"
                or die "Unexpected state event type";
            $event->{content}{my_key} == 1
                or die "Unexpected event content";

            Future->done(1);
         })
   };


test "Changes to state are included in an incremental sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [ "a.madeup.test.state" ] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => {types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_changes"
         );
      })->then( sub {
         matrix_put_room_state_synced( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_does_not_change"
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_put_room_state_synced( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 2 },
            state_key => "this_state_changes",
         );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         @{ $room->{timeline}{events} } == 1
            or die "Expected only one state event";

         assert_json_empty_list( $room->{state}{events} );

         my $event = $room->{timeline}{events}[0];
         $event->{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $event->{content}{my_key} == 2
            or die "Unexpected event content";

         Future->done(1);
      })
   };


test "Changes to state are included in an gapped incremental sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [ "a.made.up.filler.type" ], limit => 1 },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => {types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user )
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_changes"
         )
      })->then( sub {
         matrix_put_room_state_synced( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_does_not_change"
         )
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         @{ $body->{rooms}{join}{$room_id}{state}{events} } == 2
            or die "Expected two state events";

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 2 },
            state_key => "this_state_changes",
         )
      })->then( sub {
         matrix_send_filler_messages_synced( $user, $room_id, 20 );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         @{ $room->{state}{events} } == 1
            or die "Expected only one state event";

         my $event = $room->{state}{events}[0];
         $event->{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $event->{content}{my_key} == 2
            or die "Unexpected event content";

         Future->done(1);
      })
   };


test "State from remote users is included in the timeline in an incremental sync",
    requires => [ local_user_fixture( with_events => 0 ), remote_user_fixture(),
                  qw( can_sync ) ],

    check => sub {
        my ( $user, $remote_user ) = @_;

        my ( $filter_id, $room_id );

        my $filter = {
            room => {
                timeline  => { types => [ "a.madeup.test.state" ] },
                state     => { types => [ "a.madeup.test.state" ] },
                ephemeral => { types => [] },
            },
            presence => {types => [] },
        };

        matrix_create_filter( $user, $filter )->then( sub {
            ( $filter_id ) = @_;

            matrix_create_room( $remote_user );
        })->then( sub {
            ( $room_id ) = @_;
            matrix_invite_user_to_room_synced(
               $remote_user, $user, $room_id
            );
        })->then( sub {
            matrix_join_room_synced( $user, $room_id );
        })->then( sub {
            matrix_sync( $user, filter => $filter_id );
        })->then( sub {
            matrix_do_and_wait_for_sync( $user,
               do => sub {
                  matrix_put_room_state( $remote_user, $room_id,
                     type    => "a.madeup.test.state",
                     content => { "my_key" => 1 }
                  );
               },
               check => sub {
                  sync_timeline_contains( $_[0], $room_id, sub {
                     $_[0]->{type} eq "a.madeup.test.state";
                  });
               },
            );
        })->then( sub {
            matrix_sync_again( $user, filter => $filter_id );
        })->then( sub {
            my ( $body ) = @_;

            my $room = $body->{rooms}{join}{$room_id};
            assert_json_keys( $room, qw( timeline state ephemeral ));

            assert_json_empty_list( $room->{state}{events} );

            @{ $room->{timeline}{events} } == 1
                or die "Expected one timeline event";

            my $event = $room->{timeline}{events}[0];
            $event->{type} eq "a.madeup.test.state"
                or die "Unexpected state event type";
            $event->{content}{my_key} == 1
                or die "Unexpected event content";

            Future->done(1);
         })
   };


test "A full_state incremental update returns all state",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = { room => {
          timeline => { limit => 2 },
          state     => { types => [ "a.madeup.test.state" ] },
      } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_changes"
         );
      })->then( sub {
         matrix_put_room_state_synced( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_does_not_change"
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_empty_list( $body->{rooms}{join}{$room_id}{state}{events} );

         @{ $body->{rooms}{join}{$room_id}{timeline}{events} } == 2
             or die "Expected two timeline events";

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 2 },
            state_key => "this_state_changes",
         );
      })->then( sub {
         matrix_send_filler_messages_synced( $user, $room_id, 10 );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id, full_state => 'true' );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw(timeline state ephemeral ));

         @{ $room->{state}{events} } == 2
            or die "Expected two state events";
         my $got_key_1 = 0;
         my $got_key_2 = 0;
         foreach my $event (@{ $room->{state}{events} }) {
             $event->{type} eq "a.madeup.test.state"
                 or die "Unexpected type";
             my $my_key = $event->{content}{my_key};
             if( $event->{state_key} eq 'this_state_does_not_change' ) {
                 $got_key_1++;
                 $my_key == 1
                     or die "Unexpected event content ".$my_key;
             } elsif( $event->{state_key} eq 'this_state_changes' ) {
                 $got_key_2++;
                 $my_key == 2
                     or die "Unexpected event content ".$my_key;
             } else {
                 die "Unexpected state key ".$event->{state_key};
             }
         }
         $got_key_1 == 1 or die "missing this_state_does_not_change";
         $got_key_2 == 1 or die "missing this_state_changes";

         @{ $room->{timeline}{events} } == 2
             or die "Expected two timeline event";
         foreach my $i (0..1) {
             my $event = $room->{timeline}{events}[$i];
             $event->{type} eq "a.made.up.filler.type"
                 or die "Unexpected type ".$event->{type};
         }

         Future->done(1);
      })
   };


test "When user joins a room the state is included in the next sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => { types => [] },
      };

      Future->needs_all(
         matrix_create_filter( $user_a, $filter ),
         matrix_create_filter( $user_b, $filter ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user_a, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "",
         );
      })->then( sub {
         matrix_invite_user_to_room_synced(
            $user_a, $user_b, $room_id
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         matrix_join_room_synced( $user_b, $room_id );
      })->then( sub {
         matrix_sync_again( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         @{ $room->{state}{events} } == 1
            or die "Expected only one state event";

         my $event = $room->{state}{events}[0];
         $event->{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $event->{content}{my_key} == 1
            or die "Unexpected event content";

         Future->done(1);
      })
   };


test "A change to displayname should not result in a full state sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],
   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => { types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state_synced( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => ""
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         @{ $body->{rooms}{join}{$room_id}{state}{events} } == 1
            or die "Expected one state event";

         matrix_put_room_state( $user, $room_id,
            type      => "m.room.member",
            content   => { "membership" => "join",
                           "displayname" => "boris" },
            state_key => $user->user_id,
         );
      })->then( sub {
         matrix_send_room_text_message_synced( $user, $room_id,
            body => "A message to wait on because the m.room.member doesn't come down /sync"
         );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         # The m.room.member event is filtered out; the only thing which could
         # come back is therefore the madeup.test.state event, which shouldn't,
         # as this is an incremental sync.
         not keys %{ $body->{rooms}{join} } or die "Expected empty sync";

         Future->done(1);
      })
   };


test "A change to displayname should appear in incremental /sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id_1, $event_id_2 );

      matrix_create_filter( $user, {} )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {

         matrix_put_room_state( $user, $room_id,
            type      => "m.room.member",
            content   => { "membership" => "join",
                           "displayname" => "boris" },
            state_key => $user->user_id,
         );
      })->then( sub {
         my ( $result ) = @_;
         $event_id_1 = $result->{event_id};

         matrix_send_room_text_message_synced( $user, $room_id,
            body => "A message to wait on because the m.room.member might not come down /sync"
          );
      })->then( sub {
         ( $event_id_2 ) = @_;

         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         my $timeline = $room->{timeline}{events};

         log_if_fail "Room", $room;

         assert_eq( scalar @{ $timeline }, 2, "Expected 2 events");
         assert_eq( $timeline->[0]{event_id}, $event_id_1, "First event ID" );
         assert_eq( $timeline->[1]{event_id}, $event_id_2, "Second event ID" );

         Future->done(1);
      });
   };


test "When user joins a room the state is included in a gapped sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync )],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [ "a.made.up.filler.type" ], limit => 1 },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => { types => [] },
      };

      Future->needs_all(
         matrix_create_filter( $user_a, $filter ),
         matrix_create_filter( $user_b, $filter ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

         matrix_create_room( $user_a )
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $user_a, $room_id,
            type => "a.madeup.test.state",
            content => { "my_key" => 1 },
            state_key => ""
         )
      })->then( sub {
         matrix_invite_user_to_room_synced(
            $user_a, $user_b, $room_id
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b);
      })->then( sub {
         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         matrix_send_filler_messages_synced( $user_a, $room_id, 20 );
      })->then( sub {
         matrix_sync_again( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         @{ $room->{state}{events} } == 1
            or die "Expected only one state event";

         my $event = $room->{state}{events}[0];
         $event->{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $event->{content}{my_key} == 1
            or die "Unexpected event content";

         Future->done(1);
      })
   };


test "When user joins and leaves a room in the same batch, the full state is still included in the next sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
            include_leave => JSON::true,
         },
         presence => { types => [] },
      };

      Future->needs_all(
         matrix_create_filter( $user_a, $filter ),
         matrix_create_filter( $user_b, $filter ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         log_if_fail "Room id", $room_id;

         matrix_put_room_state( $user_a, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "",
         );
      })->then( sub {
         matrix_invite_user_to_room_synced(
            $user_a, $user_b, $room_id
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         matrix_leave_room_synced( $user_b, $room_id );
      })->then( sub {
         matrix_sync_again( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         assert_json_keys( $room, qw( timeline state ));
         my $eventcount = scalar @{ $room->{state}{events} };
         $eventcount == 1 or
             die "Expected one state event, got $eventcount";

         my $event = $room->{state}{events}[0];
         $event->{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $event->{content}{my_key} == 1
            or die "Unexpected event content";

         Future->done(1);
      })
   };

# Test to check that current state events appear in the timeline,
# even if they were set during a period the user couldn't see.
# See bug https://github.com/matrix-org/matrix-ios-sdk/issues/341
test "Current state appears in timeline in private history",
   requires => [ local_user_fixtures( 3, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $creator, $syncer, $invitee ) = @_;

      my ( $room_id );

      matrix_create_room( $creator )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $syncer, $room_id )
      })->then( sub {
         matrix_set_room_history_visibility( $creator, $room_id, "joined" )
      })->then( sub {
         matrix_invite_user_to_room( $creator, $invitee, $room_id )
      })->then( sub {
         matrix_sync( $syncer )
      })->then( sub {
         matrix_leave_room( $syncer, $room_id )
      })->then( sub {
         matrix_join_room( $invitee, $room_id )
      })->then( sub {
         matrix_join_room_synced( $syncer, $room_id )
      })->then( sub {
         matrix_sync_again( $syncer )
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         # Check that we see invitee join event
         any {
            $_->{type} eq "m.room.member"
            && $_->{state_key} eq $invitee->user_id
            && $_->{content}{membership} eq "join"
         } @{ $room->{timeline}{events} }
            or die "No join for joined user";

         Future->done( 1 );
      })
   };

test "Current state appears in timeline in private history with many messages before",
   requires => [ local_user_fixtures( 3, with_events => 0 ),
                 qw( can_sync ) ],

   # sending 50 messages can take a while
   timeout => 20,

   check => sub {
      my ( $creator, $syncer, $invitee ) = @_;

      my ( $room_id );

      matrix_create_room( $creator )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $syncer, $room_id )
      })->then( sub {
         matrix_set_room_history_visibility( $creator, $room_id, "joined" )
      })->then( sub {
         matrix_invite_user_to_room( $creator, $invitee, $room_id )
      })->then( sub {
         matrix_sync( $syncer )
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $creator, $room_id,
               body => "Message $msgnum",
            )->on_done( sub {
               log_if_fail "Sent msg $msgnum / 50";
            });
         }, foreach => [ 1 .. 50 ])
      })->then( sub {
         matrix_leave_room( $syncer, $room_id )
      })->then( sub {
         matrix_join_room( $invitee, $room_id )
      })->then( sub {
         matrix_join_room_synced( $syncer, $room_id )
      })->then( sub {
         matrix_sync_again( $syncer )
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         # Check that we see invitee join event
         any {
            $_->{type} eq "m.room.member"
            && $_->{state_key} eq $invitee->user_id
            && $_->{content}{membership} eq "join"
         } @{ $room->{timeline}{events} }
            or die "No join for joined user";

         Future->done( 1 );
      })
   };



test "Current state appears in timeline in private history with many messages after",
   requires => [ local_user_fixtures( 3, with_events => 0 ),
                 qw( can_sync ) ],

   # sending 50 messages can take a while
   timeout => 20,

   check => sub {
      my ( $creator, $syncer, $invitee ) = @_;

      my ( $room_id );

      matrix_create_room( $creator )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $syncer, $room_id )
      })->then( sub {
         matrix_set_room_history_visibility( $creator, $room_id, "joined" )
      })->then( sub {
         matrix_invite_user_to_room( $creator, $invitee, $room_id )
      })->then( sub {
         matrix_sync( $syncer )
      })->then( sub {
         matrix_leave_room( $syncer, $room_id )
      })->then( sub {
         matrix_join_room( $invitee, $room_id )
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $creator, $room_id,
               body => "Message $msgnum",
            )->on_done( sub {
               log_if_fail "Sent msg $msgnum / 50";
            });
         }, foreach => [ 1 .. 50 ])
      })->then( sub {
         matrix_join_room_synced( $syncer, $room_id )
      })->then( sub {
         matrix_sync_again( $syncer )
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         # Check that we see invitee join event
         any {
            $_->{type} eq "m.room.member"
            && $_->{state_key} eq $invitee->user_id
            && $_->{content}{membership} eq "join"
         } @{ $room->{timeline}{events} }
            or die "No join for joined user";

         Future->done( 1 );
      })
   };
