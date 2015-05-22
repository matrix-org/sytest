multi_test "Check that event streams started after a client joined a room work (SYT-1)",
    requires => [qw( http_clients do_request_json_for await_event_for flush_events_for
                          can_register can_create_private_room )],

    do => sub {
        my ( $clients, $do_request_json_for, $await_event_for, $flush_events_for ) = @_;
        my $http = $clients->[0];

        my $alice;
        my $room;

        # Register a user manually because register_new_user hits /events
        # which is precisely the behaviour we want to avoid.
        Future->needs_all(
            $http->do_request_json(
                method => "POST",
                uri     => "/register",
                content => {
                    type     => "m.login.password",
                    user     => "90jira-SYT-1_alice",
                    password => "an0th3r s3kr1t",
                },
            )
        )->then( sub {
            my ( $body ) = @_;
            my $user_id = $body->{user_id};
            my $access_token = $body->{access_token};
            $alice = User($http, $user_id, $access_token, undef, [], undef);
            pass "Registered user";
            # Have Alice create a new private room
            $do_request_json_for->( $alice,
                method => "POST",
                uri     => "/createRoom",
                content => { visibility => "private" },
            )
        })->then( sub {
            ( $room ) = @_;
            pass "Created a room";
            # Now that we've joined a room, flush the event stream to get
            # a stream token from before we send a message.
            $flush_events_for->( $alice );
        })->then( sub {
            # Alice sends a message
            $do_request_json_for->( $alice,
                method => "POST",
                uri     => "/rooms/$room->{room_id}/send/m.room.message",
                content => {
                    msgtype => "m.message",
                    body => "Room message for 90jira-SYT-1"
                },
            )
         })->then( sub {
            my ( $body ) = @_;
            my $event_id = $body->{event_id};
            # Wait for the message we just sent.
            Future->wait_any(
                $await_event_for->( $alice, sub {
                    my ( $event ) = @_;
                    return unless $event->{type} eq "m.room.message";
                    return unless $event->{event_id} eq $event_id;
                    return 1;
                }),
                delay( 2 )->then_fail(
                    "Timed out waiting for message for Alice"
                )
            );
        })->then( sub {
            pass "Alice saw her message";
            Future->done(1);
        });
    };
