test "Can sync a joined room",
    requires => [qw( first_api_client can_sync )],

    check => sub {
        my ( $http ) = @_;
        my ( $user, $filter_id, $room_id );
        matrix_register_sync_user( $http )->then( sub {
            ( $user ) = @_;
            matrix_create_room( $user )
        })->then( sub {
            ( $room_id ) = @_;
            matrix_create_filter( $user, {
                room => { timeline => { limit => 10 }}
            })
        })->then( sub {
            ( $filter_id ) = @_;
            matrix_sync( $user, filter => $filter_id )
        })->then( sub {
            my ( $body ) = @_;
            my $room = $body->{rooms}{joined}{$room_id};
            require_json_keys( $room, qw( event_map timeline state ephemeral ));
            require_json_keys( $room->{timeline}, qw( events limited prev_batch ));
            require_json_keys( $room->{state}, qw( events ));
            require_json_keys( $room->{ephemeral}, qw( events ));
            require_json_keys( $room->{event_map}, @{$room->{timeline}{events}} );
            require_json_keys( $room->{event_map}, @{$room->{state}{events}} );
            matrix_sync( $user, filter => $filter_id, since => $body->{next_batch} );
        })->then( sub {
            my ( $body ) = @_;
            my $room = $body->{rooms}{joined}{$room_id};
            (!defined $room) or die "Unchanged rooms shouldn't be in the sync response";
            Future->done(1)
        })
    }
