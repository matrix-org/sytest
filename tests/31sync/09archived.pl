test "Left rooms appear in the archived section of sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id );

      matrix_register_user_with_filter( $http, {} )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_leave_room( $user, $room_id );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{archived}{$room_id};
         assert_json_keys( $room, qw( event_map timeline state ));

         Future->done(1);
      });
   };


test "Newly left rooms appear in the archived section of incremental sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $next );

     matrix_register_user_with_filter( $http, {} )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next = $body->{next_batch};

         matrix_leave_room( $user, $room_id );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{archived}{$room_id};
         assert_json_keys( $room, qw( event_map timeline state ));

         Future->done(1);
      });
   };


test "Newly left rooms appear in the archived section of gapped sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id_1, $room_id_2, $next );

      my $filter = {
         room => { timeline => { limit => 1 } },
      };

      matrix_register_user_with_filter( $http, {} )->then( sub {
         ( $user, $filter_id ) = @_;

         Future->needs_all(
            matrix_create_room( $user )->on_done( sub { ( $room_id_1 ) = @_; } ),
            matrix_create_room( $user )->on_done( sub { ( $room_id_2 ) = @_; } ),
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next = $body->{next_batch};

         matrix_leave_room( $user, $room_id_1 );
      })->then( sub {
         # Pad out the timeline with filler messages to create a "gap" between
         # this sync and the next. It's useful to test this since
         # implementations of matrix are likely to take different code paths
         # if there were many messages between a since that if there were only
         # a few.
         Future->needs_all( map {
            matrix_send_room_message( $user, $room_id_2,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 20 );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{archived}{$room_id_1};
         assert_json_keys( $room, qw( event_map timeline state ));

         Future->done(1);
      });
   };


test "Left rooms appear in the archived section of full state sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $next );

      matrix_register_user_with_filter( $http, {} )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next = $body->{next_batch};

         matrix_leave_room( $user, $room_id );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id,
             since => $next, full_state => 'true');
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{archived}{$room_id};
         assert_json_keys( $room, qw( event_map timeline state ));

         Future->done(1);
      });
   };


test "Archived rooms only contain history from before the user left",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id, $next_b );

      my $filter = {
         room => {
            timeline => { types => [ "m.room.message" ] },
            state => { types => [ "a.madeup.test.state" ] },
         },
      };

      Future->needs_all(
         matrix_register_user_with_filter( $http, $filter ),
         matrix_register_user_with_filter( $http, $filter ),
      )->then( sub {
         ( $user_a, $filter_id_a, $user_b, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         $next_b = $body->{next_batch};

         matrix_send_room_text_message( $user_a, $room_id, body => "before" );
      })->then( sub {
         matrix_put_room_state( $user_a, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => "before" },
            state_key => "",
         );
      })->then( sub {
         matrix_leave_room( $user_b, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $user_a, $room_id, body => "after" );
      })->then( sub {
         matrix_put_room_state( $user_a, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => "after" },
            state_key => "",
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{archived}{$room_id};
         assert_json_keys( $room, qw( event_map timeline state ));
         @{ $room->{state}{events} } == 1
            or die "Expected a single state event";
         @{ $room->{timeline}{events} } == 1
            or die "Expected a single timeline event";

         my $state_event_id = $room->{state}{events}[0];
         $room->{event_map}{ $state_event_id }{content}{my_key}
            eq "before" or die "Expected only events from before leaving";

         my $timeline_event_id = $room->{timeline}{events}[0];
         $room->{event_map}{ $timeline_event_id }{content}{body}
            eq "before" or die "Expected only events from before leaving";

         matrix_sync( $user_b, filter => $filter_id_b, since => $next_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{archived}{$room_id};
         assert_json_keys( $room, qw( event_map timeline state ));
         @{ $room->{state}{events} } == 1
            or die "Expected a single state event";
         @{ $room->{timeline}{events} } == 1
            or die "Expected a single timeline event";

         my $state_event_id = $room->{state}{events}[0];
         $room->{event_map}{ $state_event_id }{content}{my_key}
            eq "before" or die "Expected only events from before leaving";

         my $timeline_event_id = $room->{timeline}{events}[0];
         $room->{event_map}{ $timeline_event_id }{content}{body}
            eq "before" or die "Expected only events from before leaving";

         Future->done(1);
      });
   };
