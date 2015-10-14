test "State is included in the initial sync",
    requires => [qw( first_api_client can_sync )],

    check => sub {
        my ( $http ) = @_;
        my ( $user, $filter_id, $room_id );

        my $filter = {
            room => {
                timeline => { types => [] },
                state => { types => ["a.madeup.test.state"] },
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
                type => "a.madeup.test.state",
                content => { "my_key" => 1 },
            )
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
            Future->done(1)
        })
    };


test "Changes to state are included in an incremental sync",
    requires => [qw( first_api_client can_sync )],

    check => sub {
        my ( $http ) = @_;
        my ( $user, $filter_id, $room_id, $next_batch );

        my $filter = {
            room => {
                timeline => { types => [] },
                state => { types => ["a.madeup.test.state"] },
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
                type => "a.madeup.test.state",
                content => { "my_key" => 1 },
                state_key => "this_state_changes"
            )
        })->then( sub {
            matrix_put_room_state( $user, $room_id,
                type => "a.madeup.test.state",
                content => { "my_key" => 1 },
                state_key => "this_state_does_not_change"
            )
        })->then( sub {
            matrix_sync( $user, filter => $filter_id );
        })->then( sub {
            my ( $body ) = @_;
            $next_batch = $body->{next_batch};
            matrix_put_room_state( $user, $room_id,
                type => "a.madeup.test.state",
                content => { "my_key" => 2 },
                state_key => "this_state_changes",
            )
        })->then( sub {
            matrix_sync( $user, filter => $filter_id, since => $next_batch)
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
            Future->done(1)
        })
    };


test "That changes to state are included in an gapped incremental sync",
    requires => [qw( first_api_client can_sync )],

    check => sub {
        my ( $http ) = @_;
        my ( $user, $filter_id, $room_id, $next_batch );

        my $filter = {
            room => {
                timeline => { types => ["a.made.up.filler.type"], limit => 1 },
                state => { types => ["a.madeup.test.state"] },
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
                type => "a.madeup.test.state",
                content => { "my_key" => 1 },
                state_key => "this_state_changes"
            )
        })->then( sub {
            matrix_put_room_state( $user, $room_id,
                type => "a.madeup.test.state",
                content => { "my_key" => 1 },
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
                type => "a.madeup.test.state",
                content => { "my_key" => 2 },
                state_key => "this_state_changes",
            )
        })->then( sub {
            Future->needs_all( map {
                matrix_send_room_message( $user, $room_id,
                    content => { "filler" => $_ },
                    type => "a.made.up.filler.type",
                )
            } 0 .. 20 )
        })->then( sub {
            matrix_sync( $user, filter => $filter_id, since => $next_batch)
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
            Future->done(1)
        })
    };


test "When user joins a room the state is included in the next sync",
    requires => [qw( first_api_client can_sync )],

    check => sub {
        my ( $http ) = @_;
        my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id, $next_b );
        my $filter = {
            room => {
                timeline => { types => [] },
                state => { types => ["a.madeup.test.state"] },
                ephemeral => { types => [] },
            },
            presence => {types => [] },
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
            matrix_join_room( $user_b, $room_id )
        })->then( sub {
            matrix_sync( $user_b, filter => $filter_id_b, since => $next_b )
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
            Future->done(1)
        })
    };


test "When user joins a room the state is included in a gapped sync",
    requires => [qw( first_api_client can_sync )],

    check => sub {
        my ( $http ) = @_;
        my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id, $next_b );
        my $filter = {
            room => {
                timeline => { types => ["a.made.up.filler.type"], limit => 1 },
                state => { types => ["a.madeup.test.state"] },
                ephemeral => { types => [] },
            },
            presence => {types => [] },
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
            matrix_join_room( $user_b, $room_id )
        })->then( sub {
            Future->needs_all( map {
                matrix_send_room_message( $user_a, $room_id,
                    content => { "filler" => $_ },
                    type => "a.made.up.filler.type",
                )
            } 0 .. 20 )
        })->then( sub {
            matrix_sync( $user_b, filter => $filter_id_b, since => $next_b )
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
            Future->done(1)
        })
    };
