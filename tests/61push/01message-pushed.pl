multi_test "Test that a message is pushed",
   requires => [qw(
      api_clients test_http_server_uri_base await_http_request

      can_create_private_room
   )],

   do => sub {
      my ( $clients, $test_http_server_uri_base, $await_http_request ) = @_;

      my $http = $clients->[0];

      my $alice;
      my $bob;
      my $room_id;

      # We use the version of register new user that doesn't start the event
      # stream for Alice. Starting an event stream will make presence
      # consider Alice to be online. If presence considers alice to be online
      # then Alice might stop receiving push messages.
      # We need to register two users because you are never pushed for
      # messages that you send yourself.
      Future->needs_all(
         matrix_register_user( $http, "50push-01-alice", with_events => 0 ),
         matrix_register_user( $http, "50push-01-bob",   with_events => 0 ),
      )->SyTest::pass_on_done( "Registered users" )
      ->then( sub {
         ( $alice, $bob ) = @_;

         # Have Alice create a new private room
         matrix_create_room( $alice,
            visibility => "private",
         )
      })->then( sub {
         ( $room_id ) = @_;
         # Flush Bob's event stream so that we get a token from before
         # Alice sending the invite request.
         flush_events_for( $bob )
      })->then( sub {
         # Now alice can invite Bob to the room.
         # We also wait for the push notification for it

         Future->needs_all(
            await_event_for( $bob, sub {
               my ( $event ) = @_;
               return unless $event->{type} eq "m.room.member" and
                  $event->{room_id} eq $room_id and
                  $event->{state_key} eq $bob->user_id and
                  $event->{content}{membership} eq "invite";
               return 1;
            })->SyTest::pass_on_done( "Bob received invite" ),

            matrix_invite_user_to_room( $alice, $bob, $room_id ),
         )
      })->then( sub {
         # Bob accepts the invite by joining the room
         matrix_join_room( $bob, $room_id )
      })->then( sub {
         # Now that Bob has joined the room, we will create a pusher for
         # Alice. This may race with Bob joining the room. So the first
         # message received may be due to Bob joining rather than the
         # message that Bob sent.
         do_request_json_for( $alice,
            method  => "POST",
            uri     => "/api/v1/pushers/set",
            content => {
               profile_tag         => "tag",
               kind                => "http",
               app_id              => "sytest",
               app_display_name    => "sytest_display_name",
               device_display_name => "device_display_name",
               pushkey             => "a_push_key",
               lang                => "en",
               data                => {
                  url => "$test_http_server_uri_base/alice_push",
               },
            },
         )->SyTest::pass_on_done( "Alice's pusher created" )
      })->then( sub {
         # Bob sends a message that should be pushed to Alice, since it is
         # in a "1:1" room with Alice

         Future->needs_all(
            # TODO(check that the HTTP poke is actually the poke we wanted)
            $await_http_request->( "/alice_push", sub {
               my ( $request ) = @_;
               my $body = $request->body_from_json;

               return unless $body->{notification}{type};
               return unless $body->{notification}{type} eq "m.room.message";
               return 1;
            })->then( sub {
               my ( $request ) = @_;

               $request->respond( HTTP::Response->new( 200, "OK", [], "" ) );
               Future->done( $request );
            }),

            do_request_json_for( $bob,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/send/m.room.message",
               content => {
                  msgtype => "m.text",
                  body    => "Room message for 50push-01message-pushed"
               },
            )->SyTest::pass_on_done( "Message sent" ),
         )
      })->then( sub {
         my ( $request ) = @_;
         my $body = $request->body_from_json;

         log_if_fail "Request body", $body;

         require_json_keys( my $notification = $body->{notification}, qw(
            id room_id type sender content devices counts
         ));
         require_json_keys( $notification->{counts}, qw(
            unread
         ));
         require_json_keys( $notification->{devices}[0], qw(
            app_id pushkey pushkey_ts data tweaks
         ));
         require_json_keys( my $content = $notification->{content}, qw(
            msgtype body
         ));

         $content->{body} eq "Room message for 50push-01message-pushed" or
            die "Unexpected message body";

         pass "Alice was pushed";  # Alice has gone down the stairs
         Future->done(1);
      });
   };
