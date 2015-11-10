multi_test "Multiple calls to /sync should not cause 500 errors",
    requires => [qw(first_api_client can_sync can_send_message 
                    can_post_room_receipts)],
    check => sub {
        my ( $http ) = @_;

        my ( $user, $filter_id, $room_id, $message_event_id );

        my $filter = {
           room => {
              timeline  => { types => ['m.room.message'] },
              state     => { types => [] },
              ephemeral => {},
           },
           presence => { types => [] },
        };

        matrix_register_user_with_filter( $http, $filter )->then( sub {
            ( $user, $filter_id ) = @_;

            matrix_create_room( $user )
                ->SyTest::pass_on_done( "User A created a room" );
        })->then( sub {
            ( $room_id ) = @_;

            matrix_typing( $user, $room_id, typing => 1, timeout => 30000 )
                ->SyTest::pass_on_done( "Sent typing notification" );
        })->then( sub {
            matrix_send_room_message( $user, $room_id,
                                      content => { msgtype => "m.message",
                                                   body => "message" })
                ->SyTest::pass_on_done( "Sent message" );
        })->then( sub {
            ( $message_event_id ) = @_;

            matrix_advance_room_receipt( $user, $room_id,
                                         "m.read" => $message_event_id )
                ->SyTest::pass_on_done( "Updated read receipt" );
        })->then( sub {
            matrix_sync( $user, filter => $filter_id )
                ->SyTest::pass_on_done( "Completed first sync" );
        })->then( sub {
            my ( $body ) = @_;

            my $room = $body->{rooms}{joined}{$room_id};

            @{ $room->{ephemeral}{events} } == 2
                or die "Expected two ephemeral events";

            @{ $room->{timeline}{events} } == 1
                or die "Expected one timeline event";

            matrix_sync( $user, filter => $filter_id )
                ->SyTest::pass_on_done( "Completed second sync" );
        })->then( sub {
            my ( $body ) = @_;

            my $room = $body->{rooms}{joined}{$room_id};

            @{ $room->{ephemeral}{events} } == 2
                or die "Expected two ephemeral events";

            Future->done(1);
        });
   };
