test "State is included in the initial sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => {types => [] },
      };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user, $room_id,
            type    => "a.madeup.test.state",
            content => { "my_key" => 1 },
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ephemeral ));
         @{ $room->{state}{events} } == 1
            or die "Expected only one state event";

         my $event_id = $room->{state}{events}[0];
         $room->{event_map}{$event_id}{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $room->{event_map}{$event_id}{content}{my_key} == 1
            or die "Unexpected event content";

         Future->done(1);
      })
   };


test "Changes to state are included in an incremental sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $next_batch );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => {types => [] },
      };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_changes"
         );
      })->then( sub {
         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_does_not_change"
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};
         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 2 },
            state_key => "this_state_changes",
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next_batch );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ephemeral ));
         @{ $room->{state}{events} } == 1
            or die "Expected only one state event";

         my $event_id = $room->{state}{events}[0];
         $room->{event_map}{$event_id}{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $room->{event_map}{$event_id}{content}{my_key} == 2
            or die "Unexpected event content";

         Future->done(1);
      })
   };


test "Changes to state are included in an gapped incremental sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $next_batch );

      my $filter = {
         room => {
            timeline  => { types => [ "a.made.up.filler.type" ], limit => 1 },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => {types => [] },
      };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user )
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_changes"
         )
      })->then( sub {
         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_does_not_change"
         )
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};
         @{ $body->{rooms}{joined}{$room_id}{state}{events} } == 2
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
         } 0 .. 20 );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next_batch );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ephemeral ));
         @{ $room->{state}{events} } == 1
            or die "Expected only one state event";

         my $event_id = $room->{state}{events}[0];
         $room->{event_map}{$event_id}{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $room->{event_map}{$event_id}{content}{my_key} == 2
            or die "Unexpected event content";

         Future->done(1);
      })
   };


test "A full_state incremental update returns all state",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $next_batch );

      my $filter = { room => {
          timeline => { limit => 1 },
          state     => { types => [ "a.madeup.test.state" ] },
      } };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_changes"
         );
      })->then( sub {
         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "this_state_does_not_change"
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};
         @{ $body->{rooms}{joined}{$room_id}{state}{events} } == 2
            or die "Expected two state events";

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 2 },
            state_key => "this_state_changes",
         );
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_message( $user, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 10 );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next_batch,
             full_state => 'true');
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ephemeral ));

         @{ $room->{state}{events} } == 2
            or die "Expected only two state events";

         my $found_state_event = 0;
         foreach my $event_id (@{ $room->{state}{events} }) {
            my $event = $room->{event_map}{$event_id};
            $event->{type} eq "a.madeup.test.state"
               or die "Unexpected type";
            $event->{state_key} eq 'this_state_changes' or next;
            $event->{content}{my_key} == 2
               or die "Unexpected event content";
            $found_state_event = 1;
         }

         $found_state_event or die "Didn't find event with state_key this_state_changes state event";

         @{ $room->{timeline}{events} } == 1
             or die "Expected only one timeline event";

         Future->done(1);
      })
   };


test "When user joins a room the state is included in the next sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id, $next_b );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => { types => [] },
      };

      Future->needs_all(
         matrix_register_user_with_filter( $http, $filter ),
         matrix_register_user_with_filter( $http, $filter ),
      )->then( sub {
         ( $user_a, $filter_id_a, $user_b, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user_a, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "",
         );
      })->then( sub {
         matrix_invite_user_to_room( $user_a, $user_b, $room_id );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         $next_b = $body->{next_batch};
         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b, since => $next_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ephemeral ));
         @{ $room->{state}{events} } == 1
            or die "Expected only one state event";

         my $event_id = $room->{state}{events}[0];
         $room->{event_map}{$event_id}{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $room->{event_map}{$event_id}{content}{my_key} == 1
            or die "Unexpected event content";

         Future->done(1);
      })
   };


test "A change to displayname should not result in a full state sync",
   requires => [qw( first_api_client can_sync )],
   bug => 'SYN-515',

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $next_batch );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => { types => [] },
      };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => ""
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};
         @{ $body->{rooms}{joined}{$room_id}{state}{events} } == 1
            or die "Expected one state event";

         matrix_put_room_state( $user, $room_id,
            type      => "m.room.member",
            content   => { "membership" => "join",
                           "displayname" => "boris" },
            state_key => $user->user_id,
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next_batch );
      })->then( sub {
         my ( $body ) = @_;

         # The m.room.member event is filtered out; the only thing which could
         # come back is therefore the madeup.test.state event, which shouldn't,
         # as this is an incremental sync.
         @{ $body->{rooms}{joined}{$room_id}{state}{events} } == 0
            or die "Expected no state events";

         Future->done(1);
      })
   };


test "When user joins a room the state is included in a gapped sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id, $next_b );

      my $filter = {
         room => {
            timeline  => { types => [ "a.made.up.filler.type" ], limit => 1 },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => { types => [] },
      };

      Future->needs_all(
         matrix_register_user_with_filter( $http, $filter ),
         matrix_register_user_with_filter( $http, $filter ),
      )->then( sub {
         ( $user_a, $filter_id_a, $user_b, $filter_id_b ) = @_;
         matrix_create_room( $user_a )
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state( $user_a, $room_id,
            type => "a.madeup.test.state",
            content => { "my_key" => 1 },
            state_key => ""
         )
      })->then( sub {
         matrix_invite_user_to_room( $user_a, $user_b, $room_id )
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b);
      })->then( sub {
         my ( $body ) = @_;

         $next_b = $body->{next_batch};
         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_message( $user_a, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 20 );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b, since => $next_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ephemeral ));
         @{ $room->{state}{events} } == 1
            or die "Expected only one state event";

         my $event_id = $room->{state}{events}[0];
         $room->{event_map}{$event_id}{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $room->{event_map}{$event_id}{content}{my_key} == 1
            or die "Unexpected event content";

         Future->done(1);
      })
   };


test "When user joins and leaves a room in the same batch, the full state is still included in the next sync",
   bug => 'SYN-514',
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id, $next_b );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [ "a.madeup.test.state" ] },
            ephemeral => { types => [] },
         },
         presence => { types => [] },
      };

      Future->needs_all(
         matrix_register_user_with_filter( $http, $filter ),
         matrix_register_user_with_filter( $http, $filter ),
      )->then( sub {
         ( $user_a, $filter_id_a, $user_b, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user_a, $room_id,
            type      => "a.madeup.test.state",
            content   => { "my_key" => 1 },
            state_key => "",
         );
      })->then( sub {
         matrix_invite_user_to_room( $user_a, $user_b, $room_id );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         $next_b = $body->{next_batch};
         matrix_join_room( $user_b, $room_id );
      })->then( sub {
         matrix_leave_room( $user_b, $room_id );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b, since => $next_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{archived}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ephemeral ));
         my $eventcount = scalar @{ $room->{state}{events} };
         $eventcount == 1 or
             die "Expected one state event, got $eventcount";

         my $event_id = $room->{state}{events}[0];
         $room->{event_map}{$event_id}{type} eq "a.madeup.test.state"
            or die "Unexpected state event type";
         $room->{event_map}{$event_id}{content}{my_key} == 1
            or die "Unexpected event content";

         Future->done(1);
      })
   };
