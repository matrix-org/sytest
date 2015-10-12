test "That state is included in the initial sync",
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
            ( $user,  $filter_id ) = @_;
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
            @{$room->{state}{events}} == 1
                or die "Expected only one state event";
            my $event_id = $room->{state}{events}[0];
            $room->{event_map}{$event_id}{type} eq "a.madeup.test.state"
                or die "Unexpected state event type";
            $room->{event_map}{$event_id}{content}{my_key} == 1
                or die "Unexpected event content";
            Future->done(1)
        })
    };

test "That changes to state are included in an incremental sync",
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
            ( $user,  $filter_id ) = @_;
            matrix_create_room( $user )
        })->then( sub {
            ( $room_id ) = @_;
            Future->needs_all(
                matrix_put_room_state( $user, $room_id,
                    type => "a.madeup.test.state",
                    content => { "my_key" => 1 },
                    state_key => "this_state_changes"
                ),
                matrix_put_room_state( $user, $room_id,
                    type => "a.madeup.test.state",
                    content => { "my_key" => 1 },
                    state_key => "this_state_does_not_change"
                ),
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
            @{$room->{state}{events}} == 1
                or die "Expected only one state event";
            my $event_id = $room->{state}{events}[0];
            $room->{event_map}{$event_id}{type} eq "a.madeup.test.state"
                or die "Unexpected state event type";
            $room->{event_map}{$event_id}{content}{my_key} == 2
                or die "Unexpected event content";
            Future->done(1)
        })
    };
