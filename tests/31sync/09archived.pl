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
         require_json_keys( $room, qw( event_map timeline state ));

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
         my ($body ) = @_;

         $next = $body->{next_batch};

         matrix_leave_room( $user, $room_id );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{archived}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ));

         Future->done(1);
      });
   };

test "Newly left rooms appear in the archived section of gapped sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id_1, $room_id_2, $next );

      matrix_register_user_with_filter( $http, {} )->then( sub {
         ( $user, $filter_id ) = @_;

         Future->needs_all(
            matrix_create_room( $user )->on_done( sub { ( $room_id_1 ) = @_; } ),
            matrix_create_room( $user )->on_done( sub { ( $room_id_2 ) = @_; } ),
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ($body ) = @_;

         $next = $body->{next_batch};

         matrix_leave_room( $user, $room_id_1 );
      })->then( sub {
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
         require_json_keys( $room, qw( event_map timeline state ));

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
            timeline => { types => ["m.room.message"] },
            state => { types => ["a.madeup.test.state"] },
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

         matrix_invite_user_to_room( $user_a, $user_b, $room_id );
      })->then( sub {
         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         matrix_sync( $user_b, $filter_id_b );
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
         require_json_keys( $room, qw( event_map timeline state ));
         @{ $room->{state}{events} } == 1
            or die "Expected a single state event";
         @{ $room->{timeline}{events} } == 1
            or die "Expected a single timeline event";
         $room->{event_map}{$room->{state}{events}[0]}{content}{my_key}
            eq "before" or die "Expected only events from before leaving";
         $room->{event_map}{$room->{timeline}{events}[0]}{content}{body}
            eq "before" or die "Expected only events from before leaving";

         matrix_sync( $user_b, filter => $filter_id_b, since => $next_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{archived}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ));
         @{ $room->{state}{events} } == 1
            or die "Expected a single state event";
         @{ $room->{timeline}{events} } == 1
            or die "Expected a single timeline event";
         $room->{event_map}{$room->{state}{events}[0]}{content}{my_key}
            eq "before" or die "Expected only events from before leaving";
         $room->{event_map}{$room->{timeline}{events}[0]}{content}{body}
            eq "before" or die "Expected only events from before leaving";

         Future->done(1);
      });
   };
