multi_test "Test that a message is pushed",
    requires => [qw( http_clients do_request_json_for await_event_for flush_events_for
                    test_http_server_address await_http_request
                    can_register can_create_private_room)],
    do => sub {
        my (
            $clients, $do_request_json_for, $await_event_for,
            $flush_events_for, $test_http_server_address,
            $await_http_request) = @_;

        my $http = $clients->[0];

        my $alice;
        my $bob;
        my $room;


        # Use our own version of register new user as we don't want to start an
        # event stream for Alice. Starting an event stream will make presence
        # consider Alice to be online. If presence considers alice to be online
        # then Alice might stop receiving push messages.
        my $register_new_user = sub {
            my ( $user_id ) = @_;
            $http->do_request_json(
                method => "POST",
                uri     => "/register",
                content => {
                    type     => "m.login.password",
                    user     => $user_id,
                    password => "an0th3r s3kr1t",
                },
            )->then(sub {
                my ( $body ) = @_;
                my $user_id = $body->{user_id};
                my $access_token = $body->{access_token};
                Future->done(
                    User($http, $user_id, $access_token, undef, [], undef)
                );
            })
        };

        # We need to register two users because you are never pushed for
        # messages that you send yourself.
        Future->needs_all(
            $register_new_user->("50push-01-alice"),
            $register_new_user->("50push-01-bob"),
        )->then( sub {
            ( $alice, $bob ) = @_;
            pass "Registered users";
            # Have Alice create a new private room
            $do_request_json_for->( $alice,
                method => "POST",
                uri     => "/createRoom",
                content => { visibility => "private" },
            )
        })->then( sub {
            ( $room ) = @_;
            # Flush Bob's event stream so that we get a token from before
            # Alice sending the invite request.
            $flush_events_for->( $bob )
        })->then( sub {
            # Now alice can invite Bob to the room.
            $do_request_json_for->( $alice,
                method => "POST",
                uri    => "/rooms/$room->{room_id}/invite",
                content => { user_id => $bob->user_id },
            );
        })->then( sub {
            Future->wait_any(
                $await_event_for->( $bob, sub {
                    my ( $event ) = @_;
                    return unless $event->{type} eq "m.room.member" and
                        $event->{room_id} eq $room->{room_id} and
                        $event->{state_key} eq $bob->user_id and
                        $event->{content}{membership} eq "invite";
                    return 1;
                }),
                delay( 10 )
                    ->then_fail( "Timed out waiting for invite" ),
            );
        })->then( sub {
            # Bob accepts the invite by joining the room
            pass "Bob received invite";
            $do_request_json_for->( $bob,
                method => "POST",
                uri    => "/rooms/$room->{room_id}/join",
                content => {},
            )
        })->then( sub {
            # Now that Bob has joined the room, we will create a pusher for
            # Alice. This may race with Bob joining the room. So the first
            # message received may be due to Bob joining rather than the
            # message that Bob sent.
            $do_request_json_for->( $alice,
                method => "POST",
                uri     => "/pushers/set",
                content => {
                    profile_tag => "tag",
                    kind => "http",
                    app_id => "sytest",
                    app_display_name => "sytest_display_name",
                    device_display_name => "device_display_name",
                    pushkey => "a_push_key",
                    lang => "en",
                    data => {
                        url => "$test_http_server_address/alice_push",
                    },
                },
            )
        })->then( sub {
            pass "Alice's pusher created";
            # Bob sends a message that should be pushed to Alice, since it is
            # in a "1:1" room with Alice
            $do_request_json_for->( $bob,
                method => "POST",
                uri     => "/rooms/$room->{room_id}/send/m.room.message",
                content => {
                    msgtype => "m.message",
                    body => "Room message for 90jira-SYT-1"
                },
            )
        })->then( sub {
            pass "Message sent";
            # Now we wait for an HTTP poke for the push request.
            # TODO(check that the HTTP poke is actually the poke we wanted)
            Future->wait_any(
                $await_http_request->("/alice_push"),
                delay( 10 )->then_fail( "Timed out waiting for push" ),
            );
        })->then( sub {
            pass "Alice was pushed";
            Future->done(1);
        });
    };
