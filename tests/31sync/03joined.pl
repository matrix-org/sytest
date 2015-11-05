test "Can sync a joined room",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id );

      my $filter = { room => { timeline => { limit => 10 } } };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter ) = @_;

         matrix_create_room( $user )
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id )
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ephemeral ));
         require_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         require_json_keys( $room->{state}, qw( events ));
         require_json_keys( $room->{ephemeral}, qw( events ));
         require_json_keys( $room->{event_map}, @{ $room->{timeline}{events} } );
         require_json_keys( $room->{event_map}, @{ $room->{state}{events} } );

         matrix_sync( $user, filter => $filter_id, since => $body->{next_batch} );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         (!defined $room) or die "Unchanged rooms shouldn't be in the sync response";

         Future->done(1)
      })
   };


test "Full state sync includes joined rooms",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id );

      my $filter = { room => { timeline => { limit => 10 } } };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter ) = @_;

         matrix_create_room( $user )
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id )
      })->then( sub {
         my ( $body ) = @_;

         matrix_sync( $user, filter => $filter_id, since => $body->{next_batch},
             full_state => 'true');
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};

         require_json_keys( $room, qw( event_map timeline state ephemeral ));
         require_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         require_json_keys( $room->{state}, qw( events ));
         require_json_keys( $room->{ephemeral}, qw( events ));
         require_json_keys( $room->{event_map}, @{ $room->{timeline}{events} } );
         require_json_keys( $room->{event_map}, @{ $room->{state}{events} } );

         Future->done(1)
      })
   };


test "Newly joined room is included in an incremental sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $next_batch );

      my $filter = { room => { timeline => { limit => 10 } } };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id, since => $next_batch );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ephemeral ));
         require_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         require_json_keys( $room->{state}, qw( events ));
         require_json_keys( $room->{ephemeral}, qw( events ));
         require_json_keys( $room->{event_map}, @{ $room->{timeline}{events} } );
         require_json_keys( $room->{event_map}, @{ $room->{state}{events} } );

         matrix_sync( $user, filter => $filter_id, since => $body->{next_batch} );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         (!defined $room) or die "Unchanged rooms shouldn't be in the sync response";

         Future->done(1)
      })
   };


test "Newly joined room has correct timeline in incremental sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id, $next_b );

      my $filter = {
         room => {
            timeline => { types => [ "m.room.message" ], limit => 10 },
            state    => { types => [] },
         }
      };

      Future->needs_all(
         matrix_register_user_with_filter( $http, $filter )
            ->on_done( sub { ( $user_a, $filter_id_a ) = @_ } ),
         matrix_register_user_with_filter( $http, $filter )
            ->on_done( sub { ( $user_b, $filter_id_b ) = @_ } ),
      )->then( sub {
         matrix_create_room( $user_a )->on_done( sub { ( $room_id ) = @_ } );
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_text_message( $user_a, $room_id, body => "test" );
         } 0 .. 3 );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b )->on_done( sub {
            my ( $body ) = @_;

            $next_b = $body->{next_batch};
         });
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_text_message( $user_a, $room_id, body => "test" );
         } 0 .. 3 );
      })->then( sub {
         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b, since => $next_b );
      })->then( sub {
         my ( $body ) = @_;
         my $room = $body->{rooms}{joined}{$room_id};
         my $timeline = $room->{timeline};

         log_if_fail "Timeline", $timeline;

         map {
            $room->{event_map}{$_}{type} eq "m.room.message"
               or die "Only expected 'm.room.message' events";
         } @{ $timeline->{events} };

         if( @{ $timeline->{events} } == 6 ) {
            $timeline->{limited} == JSON::false
               or die "Timeline doesn't have all the events so should be limited";
         }
         else {
            require_json_boolean( $timeline->{limited} );
            $timeline->{limited} or
               die "Timeline doesn't have all the events so should be limited";
         }

         Future->done(1);
      });
   };
