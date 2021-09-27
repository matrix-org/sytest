use Future::Utils qw( repeat );

test "Can sync a joined room",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = { room => { timeline => { limit => 10 } } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $user )
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id )
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         assert_json_keys( $room->{state}, qw( events ));
         assert_json_keys( $room->{ephemeral}, qw( events ));

         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         (!defined $room) or die "Unchanged rooms shouldn't be in the sync response";

         Future->done(1)
      })
   };


test "Full state sync includes joined rooms",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync )],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = { room => { timeline => { limit => 10 } } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $user )
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id )
      })->then( sub {
         my ( $body ) = @_;

         matrix_sync_again( $user, filter => $filter_id, full_state => 'true' );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         assert_json_keys( $room->{state}, qw( events ));
         assert_json_keys( $room->{ephemeral}, qw( events ));

         Future->done(1)
      })
   };


test "Newly joined room is included in an incremental sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync )],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = { room => { timeline => { limit => 10 } } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_create_room_synced( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync_again( $user, filter => $filter_id);
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         assert_json_keys( $room->{state}, qw( events ));
         assert_json_keys( $room->{ephemeral}, qw( events ));

         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         (!defined $room) or die "Unchanged rooms shouldn't be in the sync response";

         Future->done(1)
      })
   };


test "Newly joined room has correct timeline in incremental sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync )],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id );

      my $filter = {
         room => {
            timeline => { types => [ "m.room.message" ], limit => 10 },
            state    => { types => [] },
         }
      };

      Future->needs_all(
         matrix_create_filter( $user_a, $filter )
            ->on_done( sub { ( $filter_id_a ) = @_ } ),
         matrix_create_filter( $user_b, $filter )
            ->on_done( sub { ( $filter_id_b ) = @_ } ),
      )->then( sub {
         matrix_create_room( $user_a )->on_done( sub { ( $room_id ) = @_ } );
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_text_message( $user_a, $room_id, body => "test1-$_" );
         } 0 .. 3 );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_text_message( $user_a, $room_id, body => "test2-$_" );
         } 0 .. 3 );
      })->then( sub {
         matrix_join_room_synced( $user_b, $room_id );
      })->then( sub {
         matrix_sync_again( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;
         my $room = $body->{rooms}{join}{$room_id};
         my $timeline = $room->{timeline};

         log_if_fail "Room id", $room_id;
         log_if_fail "Timeline", $timeline;

         map {
            $_->{type} eq "m.room.message"
               or die "Only expected 'm.room.message' events";
         } @{ $timeline->{events} };

         if( @{ $timeline->{events} } == 6 ) {
            assert_json_boolean( $timeline->{limited} );
            !$timeline->{limited} or
               die "Timeline has all the events so shouldn't be limited";
         }
         else {
            assert_json_boolean( $timeline->{limited} );
            $timeline->{limited} or
               die "Timeline doesn't have all the events so should be limited";
         }

         Future->done(1);
      });
   };


test "Newly joined room includes presence in incremental sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync )],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my $room_id;

      matrix_create_room( $user_a )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user_b );
      })->then( sub {
         matrix_join_room_synced( $user_b, $room_id );
      })->then( sub {
         matrix_sync_again( $user_b );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( presence ));
         assert_json_keys( $body->{presence}, qw( events ));
         assert_json_list( $body->{presence}{events} );

         my $presence = $body->{presence}{events};

         my @filtered_presence = grep {
            $_->{sender} ne $user_b->user_id
         } @$presence;

         assert_eq( scalar @filtered_presence, 1, "number of presence events" );

         assert_json_keys( $filtered_presence[0], qw( type sender content ) );
         assert_eq( $filtered_presence[0]->{type}, "m.presence" );
         assert_eq( $filtered_presence[0]->{sender}, $user_a->user_id );

         matrix_sync_again( $user_b );
      })->then( sub {
         my ( $body ) = @_;

         if ( exists $body->{presence} and exists $body->{presence}{events} ) {
            assert_json_list( $body->{presence}{events} );

            my $presence = $body->{presence}{events};

            assert_eq( scalar @$presence, 0, "number of presence events" );
         }

         Future->done(1);
      });
   };

test "Get presence for newly joined members in incremental sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync )],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my $room_id;

      matrix_create_room( $user_a )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user_a );
      })->then( sub {
         matrix_send_room_text_message_synced( $user_a, $room_id,
            body => "Wait for presence changes caused by the first sync to trickle through",
         );
      })->then( sub {
         matrix_sync_again( $user_a );
      })->then( sub {
         matrix_join_room_synced( $user_b, $room_id );
      })->then( sub {
         matrix_sync_again( $user_a );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( presence ));
         assert_json_keys( $body->{presence}, qw( events ));
         assert_json_list( $body->{presence}{events} );

         my $presence = $body->{presence}{events};
         log_if_fail "Presence", $presence;

         my @filtered_presence = grep {
            $_->{sender} ne $user_a->user_id
         } @$presence;

         assert_eq( scalar @filtered_presence, 1, "number of presence events" );

         my $presence_event = $filtered_presence[0];

         assert_json_keys( $presence_event, qw( type sender content ) );
         assert_eq( $presence_event->{type}, "m.presence" );
         assert_eq( $presence_event->{sender}, $user_b->user_id );

         matrix_sync_again( $user_a );
      })->then( sub {
         my ( $body ) = @_;

         if ( exists $body->{presence} and exists $body->{presence}{events} ) {
            assert_json_list( $body->{presence}{events} );

            my $presence = $body->{presence}{events};

            assert_eq( scalar @$presence, 0, "number of presence events" );
         }

         Future->done(1);
      });
   };
