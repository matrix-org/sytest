multi_test "Setup a room, and havve the first user leave (SPEC-216)",

    requires => [qw(
        make_test_room change_room_powerlevels
            do_request_json_for user more_users
        can_create_room
    )],

    provides => [qw( departed_room_id )],

    # User A creates a room.
    # User A invites User B to the room.
    # User B joins the room.
    # User B will set the ("madeup.test.state", "") state of the room to {
    #   "body": "S1. B's state before A left"
    # }
    # User B will send a message with body "M1. B's message before A left"
    # User B will send a message with body "M2. B's message before A left"
    # User A will leave the room.
    # User B will set the ("madeup.test.state", "") state of the room to {
    #   "body": "S2. B's state after A left"
    # }
    # User B will send a message with text "M3. B's message after A left"
    #
    do => sub {
        my (
            $make_test_room, $change_room_powerlevels, $do_request_json_for,
            $user_a, $more_users
        ) = @_;
        my $user_b = $more_users->[1];

        my $room_id;

        $make_test_room->($user_a, $user_b)->then( sub {
            ( $room_id ) = @_;

            provide departed_room_id => $room_id;

            $change_room_powerlevels->($user_a, $room_id, sub {
                my ( $levels ) = @_;
                $levels->{users}{ $user_b->user_id } = 50;
            })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "PUT",
                uri => "/rooms/$room_id/state/madeup.test.state",
                content => { "body" => "S1. B's state before A left", },
            )->on_done(sub { pass "User B set the state the first time" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "POST",
                uri => "/rooms/$room_id/send/m.room.message",
                content => {
                    "body" => "M1. B's message before A left",
                    "msgtype" => "m.room.text",
                },
            )->on_done(sub { pass "User B sent their first message" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "POST",
                uri => "/rooms/$room_id/send/m.room.message",
                content => {
                    "body" => "M2. B's message before A left",
                    "msgtype" => "m.room.text",
                },
            )->on_done(sub { pass "User B sent their second message" })
        })->then( sub {
            $do_request_json_for->( $user_a,
                method => "POST",
                uri => "/rooms/$room_id/leave",
                content => {},
            )->on_done(sub { pass "User A left the room" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "POST",
                uri => "/rooms/$room_id/send/m.room.message",
                content => {
                    "body" => "M3. B's message after A left",
                    "msgtype" => "m.room.text",
                },
            )->on_done(sub { pass "User B sent their third message" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "PUT",
                uri => "/rooms/$room_id/state/madeup.test.state",
                content => { "body" => "S2. B's state after A left", },
            )->on_done(sub { pass "User B set the state the second time" })
        })
    };


test "A departed room is still included in /initialSync (SPEC-216)",
    requires => [qw(do_request_json departed_room_id)],
    check => sub {
        my ($do_request_json, $departed_room_id) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/initialSync",
            params => { limit => 2 },
        )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( rooms ) );

            my ( $room ) = grep { $_->{room_id} eq $departed_room_id }
                @{$body->{rooms}};

            die "Departed room not in /initialSync"
                unless $room;

            require_json_keys( $room, qw(
                state messages membership
            ) );

            die "Membership is not leave"
                unless $room->{membership} eq "leave";

            my ( $madeup_test_state ) = grep { $_->{type} eq "madeup.test.state" }
                @{$room->{state}};

            die "Received state that happened after leaving the room"
                unless $madeup_test_state->{content}{body}
                    eq "S1. B's state before A left";

            die "Received message that happened after leaving the room"
                unless $room->{messages}{chunk}[0]{content}{body}
                    eq "M2. B's message before A left";

            Future->done(1);
        })
    };

test "Can get room/{roomId}/initialSync for a departed room (SPEC-216)",
    requires => [qw(do_request_json departed_room_id)],
    check => sub {
        my ($do_request_json, $departed_room_id) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/rooms/$departed_room_id/initialSync",
            params => { limit => 2 },
        )->then( sub {
            my ( $room ) = @_;

            require_json_keys( $room, qw( state messages membership ) );

            die "Membership is not leave"
                unless $room->{membership} eq "leave";

            my ( $madeup_test_state ) = grep { $_->{type} eq "madeup.test.state" }
                @{$room->{state}};

            die "Received state that happened after leaving the room"
                unless $madeup_test_state->{content}{body}
                    eq "S1. B's state before A left";

            die "Received message that happened after leaving the room"
                unless $room->{messages}{chunk}[0]{content}{body}
                    eq "M2. B's message before A left";

            die "Received presence information after leaving the room"
                if @{$room->{presence}};

            die "Received receipts after leaving the room"
                if @{$room->{receipts}};

            Future->done(1);
        })
    };

