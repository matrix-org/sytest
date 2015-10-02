multi_test "Limit on room/initialSync is reached over federation (SYN-482)",
    requires => [qw( make_test_room local_users remote_users)],

    check => sub {
        my ( $make_test_room, $local_users, $remote_users ) = @_;
        my $user_a = $local_users->[0];
        my $user_b = $remote_users->[0];
        my $room_id;
        my $messages_events;
        my $sync_events;

        $make_test_room->( [ $user_a ] )->then( sub {
            ( $room_id ) = @_;
            do_request_json_for( $user_a,
                method  => "PUT",
                uri     => "/api/v1/rooms/$room_id/state/m.room.history_visibility",
                content => { history_visibility => "invited" },
            )
        })->then( sub {
            matrix_invite_user_to_room( $user_a, $user_b, $room_id )
        })->then( sub {
            Future->needs_all(map {
                matrix_send_room_text_message( $user_a, $room_id,
                    body => "Message #$_",
                )
            } 1..3)
        })->then( sub {
            matrix_join_room( $user_b, $room_id )
        })->then( sub {
            do_request_json_for( $user_b,
                method => "GET",
                uri    => "/api/v1/rooms/$room_id/initialSync",
                params => {limit => 10},
            )
        })->then( sub {
            my ($body) = @_;
            $sync_events = $body->{messages}->{chunk};
            do_request_json_for( $user_b,
                method => "GET",
                uri    => "/api/v1/rooms/$room_id/messages",
                params => {limit => 10, dir => "b"},
            )
        })->then( sub {
            my ($body) = @_;
            $messages_events = ${body}->{chunk};
            die "Received different number of messages in"
                . " rooms/{roomId}/initialSync compared to "
                . " rooms/{roomId}/messages"
                    unless @$sync_events == @$messages_events;
            Future->done(1);
        })
    };
