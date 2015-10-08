test "Can sync a room with a single message",
    requires => [qw( first_api_client can_sync )],
    check => sub {
        my ( $http ) = @_;
        my ( $user, $filter_id, $room_id, $event_id );
        matrix_register_sync_user( $http )->then( sub {
            ( $user ) = @_;
            matrix_create_room( $user )
        })->then( sub {
            ( $room_id ) = @_;
            matrix_send_room_text_message( $user, $room_id,
                body => "A test message",
            )
        })->then( sub {
            ( $event_id ) = @_;
            matrix_create_filter( $user, {
                room => { timeline => { limit => 1 }}
            })
        })->then( sub {
            ( $filter_id ) = @_;
            matrix_sync( $user, filter => $filter_id )
        })->then( sub {
            my ( $body ) = @_;
            my $room = $body->{rooms}{joined}{$room_id};
            require_json_keys( $room, qw( event_map timeline state ephemeral ));
            require_json_keys( $room->{timeline}, qw( events limited prev_batch ));
            @{$room->{timeline}{events}} == 1
                or die "Expected only one timeline event";
            $room->{timeline}{events}[0] eq $event_id
                or die "Unexpected timeline event";
            $room->{event_map}{$event_id}{content}{body} eq "A test message"
                or die "Unexpected message body.";
            $room->{timeline}{limited}
                or die "Expected timeline to be limited";
            Future->done(1)
        })
    };
