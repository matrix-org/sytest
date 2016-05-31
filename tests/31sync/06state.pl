use Future::Utils qw( repeat );

# call /sync repeatedly until it returns a result
# with an event in the given room
# TODO: it might be good to combine this with await_event_for() at some point.
sub wait_for_event_in_room {
    my ($user, $room_id, %params) = @_;

    my $sync_params = $params{sync_params} || {};

    repeat(sub {
        # returns the sync body if the event happened, else undef
        matrix_sync( $user, %{ $sync_params } )->then( sub {
            my ( $body ) = @_;

            my $room = $body->{rooms}{join}{$room_id};

            if( $room && (scalar @{ $room->{timeline}{events}} ||
                          scalar @{ $room->{state}{events}})) {
                Future->done($body);
            } else {
                delay(0.1)->then_done(undef);
            }
        });
    }, while => sub {!$_[0]->failure and !$_[0]->get});
}

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

         matrix_put_room_state_and_wait_for_sync( $user, $room_id,
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
            matrix_invite_user_to_room_and_wait_for_sync(
               $remote_user, $user, $room_id
            );
        })->then( sub {
            matrix_join_room_and_wait_for_sync( $user, $room_id );
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
         matrix_put_room_state_and_wait_for_sync( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_does_not_change"
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_put_room_state_and_wait_for_sync( $user, $room_id,
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
         matrix_put_room_state_and_wait_for_sync( $user, $room_id,
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
         Future->needs_all( map {
            matrix_send_room_message( $user, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 19 );
      })->then( sub {
         matrix_send_room_message_and_wait_for_sync( $user, $room_id,
            content => { "filler" => 20 },
            type    => "a.made.up.filler.type",
         );
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
            matrix_invite_user_to_room_and_wait_for_sync(
               $remote_user, $user, $room_id
            );
        })->then( sub {
            matrix_join_room_and_wait_for_sync( $user, $room_id );
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
         matrix_put_room_state_and_wait_for_sync( $user, $room_id,
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
         Future->needs_all( map {
            matrix_send_room_message_and_wait_for_sync( $user, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 10 );
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
         matrix_invite_user_to_room_and_wait_for_sync(
            $user_a, $user_b, $room_id
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         matrix_join_room_and_wait_for_sync( $user_b, $room_id );
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

         matrix_put_room_state_and_wait_for_sync( $user, $room_id,
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
         matrix_send_room_text_message_and_wait_for_sync( $user, $room_id,
            body => "Waiting because matrix_put_room_state_and_wait for sync doesn't seem to work"
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
         matrix_invite_user_to_room_and_wait_for_sync(
            $user_a, $user_b, $room_id
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b);
      })->then( sub {
         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_message( $user_a, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 19 );
      })->then( sub {
         matrix_send_room_message_and_wait_for_sync( $user_a, $room_id,
            content => { "filler" => 20 },
            type    => "a.made.up.filler.type",
         );
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
         matrix_invite_user_to_room_and_wait_for_sync(
            $user_a, $user_b, $room_id
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         matrix_leave_room_and_wait_for_sync( $user_b, $room_id );
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
