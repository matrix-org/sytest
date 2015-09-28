multi_test "Setup a room, and have the first user leave (SPEC-216)",

    requires => [qw(
        make_test_room change_room_powerlevels do_request_json_for user
        more_users can_create_room
    )],

    provides => [qw( departed_room_id )],

    # User A creates a room.
    # User A invites User B to the room.
    # User B joins the room.
    # User B will set the ("m.room.name", "") state of the room to {
    #   "body": "N1. B's room name before A left"
    # }
    # User B will set the ("madeup.test.state", "") state of the room to {
    #   "body": "S1. B's state before A left"
    # }
    # User B will send a message with body "M1. B's message before A left"
    # User B will send a message with body "M2. B's message before A left"
    # User A will leave the room.
    # User B will set the ("m.room.name", "") state of the room to {
    #   "body": "N2. B's room name after A left"
    # }
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

        $make_test_room->([$user_a, $user_b])->then( sub {
            ( $room_id ) = @_;

            provide departed_room_id => $room_id;

            $change_room_powerlevels->($user_a, $room_id, sub {
                my ( $levels ) = @_;
                # Set user B's power level so that they can set the room
                # name. By default the level to set a room name is 50.
                $levels->{users}{ $user_b->user_id } = 50;
            })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "PUT",
                uri => "/api/v1/rooms/$room_id/state/m.room.name",
                content => { "name" => "N1. B's room name before A left", },
            )->on_done(sub { pass "User B set the room name the first time" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "PUT",
                uri => "/api/v1/rooms/$room_id/state/madeup.test.state",
                content => { "body" => "S1. B's state before A left", },
            )->on_done(sub { pass "User B set the state the first time" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "POST",
                uri => "/api/v1/rooms/$room_id/send/m.room.message",
                content => {
                    "body" => "M1. B's message before A left",
                    "msgtype" => "m.room.text",
                },
            )->on_done(sub { pass "User B sent their first message" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "POST",
                uri => "/api/v1/rooms/$room_id/send/m.room.message",
                content => {
                    "body" => "M2. B's message before A left",
                    "msgtype" => "m.room.text",
                },
            )->on_done(sub { pass "User B sent their second message" })
        })->then( sub {
            $do_request_json_for->( $user_a,
                method => "POST",
                uri => "/api/v1/rooms/$room_id/leave",
                content => {},
            )->on_done(sub { pass "User A left the room" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "POST",
                uri => "/api/v1/rooms/$room_id/send/m.room.message",
                content => {
                    "body" => "M3. B's message after A left",
                    "msgtype" => "m.room.text",
                },
            )->on_done(sub { pass "User B sent their third message" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "PUT",
                uri => "/api/v1/rooms/$room_id/state/m.room.name",
                content => { "name" => "N2. B's room name after A left", },
            )->on_done(sub { pass "User B set the room name the second time" })
        })->then( sub {
            $do_request_json_for->( $user_b,
                method => "PUT",
                uri => "/api/v1/rooms/$room_id/state/madeup.test.state",
                content => { "body" => "S2. B's state after A left", },
            )->on_done(sub { pass "User B set the state the second time" })
        })
    };


test "A departed room is still included in /initialSync (SPEC-216)",
    requires => [qw( do_request_json departed_room_id )],
    check => sub {
        my ($do_request_json, $departed_room_id) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/initialSync",
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

test "Can get rooms/{roomId}/initialSync for a departed room (SPEC-216)",
    requires => [qw( do_request_json departed_room_id )],
    check => sub {
        my ($do_request_json, $departed_room_id) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$departed_room_id/initialSync",
            params => { limit => 2 },
        )->then( sub {
            my ( $room ) = @_;

            require_json_keys( $room, qw( state messages membership ) );

            die "Membership is not leave"
                unless $room->{membership} eq "leave";

            my ( $madeup_test_state ) =
                grep { $_->{type} eq "madeup.test.state" } @{$room->{state}};

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

test "Can get rooms/{roomId}/state for a departed room (SPEC-216)",
    requires => [qw( do_request_json departed_room_id )],
    check => sub {
        my ($do_request_json, $departed_room_id) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$departed_room_id/state",
        )->then(sub {
            my ( $state ) = @_;

            my ( $madeup_test_state ) =
                grep { $_->{type} eq "madeup.test.state" } @{$state};

            die "Received state that happened after leaving the room"
                unless $madeup_test_state->{content}{body}
                    eq "S1. B's state before A left";

            Future->done(1);
        })
    };

test "Can get rooms/{roomId}/members for a departed room (SPEC-216)",
    requires => [qw( do_request_json departed_room_id )],
    check => sub {
        my ($do_request_json, $departed_room_id) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$departed_room_id/members",
        )->then(sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( chunk ) );

            Future->done(1);
        })
    };

test "Can get rooms/{roomId}/messages for a departed room (SPEC-216)",
    requires => [qw( do_request_json departed_room_id )],
    check => sub {
        my ($do_request_json, $departed_room_id) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$departed_room_id/messages",
            params => {limit => 2, dir => 'b'},
        )->then(sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( chunk ) );

            die "Received message that happened after leaving the room"
                unless $body->{chunk}[1]{content}{body}
                    eq "M2. B's message before A left";

            Future->done(1);
        })
    };

test "Can get rooms/{roomId}/state/m.room.name for a departed room (SPEC-216)",
    requires => [qw(do_request_json departed_room_id)],
    check => sub {
        my ($do_request_json, $departed_room_id) = @_;

        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$departed_room_id/state/m.room.name",
        )->then(sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( name ) );

            die "Received message that happened after leaving the room"
                unless $body->{name}
                    eq "N1. B's room name before A left";

            Future->done(1);
        })
    };

test "Getting messages going forward is limited for a departed room (SPEC-216)",
    requires => [qw( do_request_json departed_room_id )],
    check => sub {
        my ($do_request_json, $departed_room_id) = @_;


        # TODO: The "t10000-0_0_0_0" token format is synapse specific.
        #  However there isn't a way in the matrix C-S protocol to learn the
        #  latest token for a room that you aren't in. It may be necessary
        #  to add some extra APIs to matrix for learning this sort of thing for
        #  testing security.
        $do_request_json->(
            method => "GET",
            uri => "/api/v1/rooms/$departed_room_id/messages",
            params => {limit => 2, to => "t10000-0_0_0_0"},
        )->then(sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( chunk ) );

            die "Received message that happened after leaving the room"
                if @{$body->{chunk}};

            Future->done(1);
        })
    };

