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
            state => { types => [] },
         }
      };

      Future->needs_all(
         matrix_register_user_with_filter( $http, $filter ),
         matrix_register_user_with_filter( $http, $filter ),
      )->then( sub {
         ( $user_a, $filter_id_a, $user_b, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         Future->needs_all( map {
            matrix_send_room_text_message( $user_a, $room_id, body => "test" );
         } 0 .. 3 );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         $next_b = $body->{next_batch};

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

         if( @{ $timeline->{events} } == 6 ) {
            # We could assert that the timeline wasn't limited in this case
            # But clients will still eventually get the correct timeline
            # since they will simply make a request for scrollback that returns
            # no data.
         }
         else {
            $timeline->{limited} == JSON::true
               or die "Timeline doesn't have all the events so should be limited";
         }
      });
   };
