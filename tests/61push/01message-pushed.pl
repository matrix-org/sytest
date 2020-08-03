sub matrix_set_pusher {
   my ( $user, $location ) = @_;

   do_request_json_for(
      $user,
      method  => "POST",
      uri     => "/r0/pushers/set",
      content => {
         profile_tag         => "tag",
         kind                => "http",
         app_id              => "sytest",
         app_display_name    => "sytest_display_name",
         device_display_name => "device_display_name",
         pushkey             => "a_push_key",
         lang                => "en",
         data                => { url => $location, },
      },
   );
}

multi_test "Test that a message is pushed",
   requires => [
      # We use the version of register new user that doesn't start the event
      # stream for Alice. Starting an event stream will make presence
      # consider Alice to be online. If presence considers alice to be online
      # then Alice might stop receiving push messages.
      # We need to register two users because you are never pushed for
      # messages that you send yourself.
      local_user_fixtures( 2, with_events => 0 ),
      $main::TEST_SERVER_INFO,

      qw( can_create_private_room )
   ],

   do => sub {
      my ( $alice, $bob, $test_server_info ) = @_;

      my $room_id;

      # Have Alice create a new private room
      matrix_create_room( $alice,
         visibility => "private",
      )->then( sub {
         ( $room_id ) = @_;
         # Flush Bob's event stream so that we get a token from before
         # Alice sending the invite request.
         flush_events_for( $bob )
      })->then( sub {
         # Now alice can invite Bob to the room.
         # We also wait for the push notification for it

         Future->needs_all(
            await_event_for( $bob, filter => sub {
               my ( $event ) = @_;
               return unless $event->{type} eq "m.room.member" and
                  $event->{room_id} eq $room_id and
                  $event->{state_key} eq $bob->user_id and
                  $event->{content}{membership} eq "invite";
               return 1;
            })->SyTest::pass_on_done( "Bob received invite" ),

            matrix_invite_user_to_room( $alice, $bob, $room_id ),
            flush_events_for( $alice ),
         )
      })->then( sub {
         # Bob accepts the invite by joining the room
         matrix_join_room( $bob, $room_id )
      })->then( sub {
         await_event_for( $alice, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member";
            return 1;
         })->then( sub {
            my ( $event ) = @_;
            matrix_advance_room_receipt( $alice, $room_id,
               "m.read" => $event->{event_id}
            );
         });
      })->then( sub {
         # Now that Bob has joined the room, we will create a pusher for
         # Alice. This may race with Bob joining the room. So the first
         # message received may be due to Bob joining rather than the
         # message that Bob sent.
         matrix_set_pusher(
            $alice, $test_server_info->client_location . "/alice_push",
         )->SyTest::pass_on_done( "Alice's pusher created" )
      })->then( sub {
         # Bob sends a message that should be pushed to Alice, since it is
         # in a "1:1" room with Alice

         Future->needs_all(
            # TODO(check that the HTTP poke is actually the poke we wanted)
            await_http_request( "/alice_push", sub {
               my ( $request ) = @_;
               my $body = $request->body_from_json;

               # Respond to all requests, even if we filiter them out
               $request->respond_json( {} );

               return unless $body->{notification}{type};
               return unless $body->{notification}{type} eq "m.room.message";
               return 1;
            }),

            matrix_send_room_text_message( $bob, $room_id,
               body => "Room message for 50push-01message-pushed",
            )->SyTest::pass_on_done( "Message sent" ),
         )
      })->then( sub {
         my ( $request ) = @_;
         my $body = $request->body_from_json;

         log_if_fail "Message push request body", $body;

         assert_json_keys( my $notification = $body->{notification}, qw(
            id room_id type sender content devices counts
         ));
         assert_json_keys( $notification->{counts}, qw(
            unread
         ));
         assert_eq( $notification->{counts}->{unread}, 1, "unread count");
         assert_json_keys( $notification->{devices}[0], qw(
            app_id pushkey pushkey_ts data tweaks
         ));
         assert_json_keys( my $content = $notification->{content}, qw(
            msgtype body
         ));

         $content->{body} eq "Room message for 50push-01message-pushed" or
            die "Unexpected message body";

         pass "Alice was pushed";  # Alice has gone down the stairs

         Future->needs_all(
            await_http_request( "/alice_push", sub {
               my ( $request ) = @_;
               my $body = $request->body_from_json;

               # Respond to all requests, even if we filiter them out
               $request->respond_json( {} );

               return unless $body->{notification}{counts};
               return 1;
            }),

            # Now send a read receipt for that message
            matrix_advance_room_receipt( $alice, $notification->{room_id},
               "m.read" => $notification->{event_id}
            )->SyTest::pass_on_done( "Receipt sent" ),
         )
      })->then( sub {
         my ( $request ) = @_;
         my $body = $request->body_from_json;
         my $notification = $body->{notification};

         log_if_fail "Zero badge push request body", $body;

         assert_json_keys( $notification->{counts}, qw(
            unread
         ));
         assert_eq( $notification->{counts}{unread}, 0, "unread count");

         pass "Zero badge push received";

         Future->done(1);
      });
   };

test "Invites are pushed",
   requires => [
      local_user_fixtures( 2, with_events => 0 ),
      $main::TEST_SERVER_INFO
   ],

   check => sub {
      my ( $alice, $bob, $test_server_info ) = @_;
      my $room_id;

      matrix_set_pusher(
         $alice, $test_server_info->client_location . "/alice_push",
      )->then( sub {
         matrix_create_room( $bob, visibility => "private" );
      })->then( sub {
         ( $room_id ) = @_;

         Future->needs_all(
            await_http_request( "/alice_push", sub {
               my ( $request ) = @_;
               my $body = $request->body_from_json;

               # Respond to all requests, even if we filiter them out
               $request->respond_json( {} );

               return unless $body->{notification}{type};
               return unless $body->{notification}{type} eq "m.room.member";
               return 1;
            }),
            matrix_invite_user_to_room( $bob, $alice, $room_id ),
         );
      })->then( sub {
         my ( $request ) = @_;
         my $body = $request->body_from_json;

         log_if_fail "Message push request body", $body;

         assert_json_keys( my $notification = $body->{notification}, qw(
            id room_id type sender content devices counts
         ));
         assert_eq( $notification->{membership}, "invite", "membership");
         assert_eq( $notification->{user_is_target}, JSON::true, "user_is_target");
         assert_eq( $notification->{room_id}, $room_id, "room_id");
         assert_eq( $notification->{sender}, $bob->user_id, "sender");

         Future->done(1);
      });
   };


=head2 setup_push

   setup_push( $alice, $bob, $test_server_info, $loc )

Sets up push for $alice and creates a room with $alice and $bob. Returns a
future with the room_id of the newly created room.

=cut

sub setup_push
{
   my ( $alice, $bob, $test_server_info, $loc ) = @_;
   my $room_id;

   my $target = $test_server_info->client_location . $loc;
   matrix_set_pusher(
      $alice, $target,
   )->then( sub {
      log_if_fail "Created pusher for ".$alice->user_id." -> ".$target;
      matrix_create_room( $bob );
   })->then( sub {
      ( $room_id ) = @_;

      matrix_join_room( $alice, $room_id );
   })->then( sub {
      # we need to make sure the pusher is working.
      #
      # the problem is that, in a worker-based system, there is no guarantee
      # that the pusher worker knows about the new pusher by the time we send
      # the event: The process handling the /pushers/set request might pause
      # between responding to /pushers/set and sending out the replication
      # notification.

      # so, we have bob send messages until we get a push.

      log_if_fail "Joined room $room_id; waiting for push to start working";

      wait_for_pusher_to_work( $bob, $room_id, $loc );
   })->then( sub {
      Future->done( $room_id );
   })
}


=head2 wait_for_pusher_to_work

   wait_for_pusher_to_work( $sending_user, $room_id, $push_location )

This is mostly a helper function for setup_push, but it might also help in some
other situations when configuring a pusher.

Because setting up a pusher is asynchronous, we need to wait until it becomes
active. We do this by having a second user (who shares a room with the user
that created the pusher) send messages to the room until a push arrives.

=cut

sub wait_for_pusher_to_work
{
   my ( $sending_user, $room_id, $push_loc ) = @_;

   # a future which waits for a push to arrive
   my $push_future = await_http_request( $push_loc, sub {
       my ( $request ) = @_;
       my $body = $request->body_from_json;

       log_if_fail "Push arrived", $body;
       $request->respond_json( {} );
       return 1;
    });

   # a future which will send messages until failure or cancelled
   my $send_future = repeat {
      matrix_send_room_text_message( $sending_user, $room_id, body => "Message" ) ->
         then( sub { return delay( 0.2 ); });
   } while => sub {
      my ( $trial_f ) = @_;
      return $trial_f->result;
   };

   # wait until we either get a push, or the send fails. In either
   # case wait_any will cancel the other future.
   return Future->wait_any(
      $push_future, $send_future
   );
}

sub check_received_push_with_name
{
   my ( $bob, $room_id, $loc, $room_name ) = @_;

   Future->needs_all(
      await_http_request( $loc, sub {
         my ( $request ) = @_;
         my $body = $request->body_from_json;

         # Respond to all requests, even if we filiter them out
         $request->respond_json( {} );

         return unless $body->{notification}{type};
         return unless $body->{notification}{type} eq "m.room.message";
         return 1;
      }),
      matrix_send_room_text_message( $bob, $room_id,
         body => "Message",
      ),
   )->then( sub {
      my ( $request ) = @_;
      my $body = $request->body_from_json;

      log_if_fail "Message push request body", $body;

      assert_json_keys( my $notification = $body->{notification}, qw(
         id room_id type sender content devices counts
      ));

      assert_eq( $notification->{room_id}, $room_id, "room_id");
      assert_eq( $notification->{sender}, $bob->user_id, "sender");
      assert_eq( $notification->{room_name}, $room_name, "room_name");

      Future->done(1);
   });
}

test "Rooms with names are correctly named in pushes",
   requires => [
      local_user_fixtures( 2, with_events => 0 ),
      $main::TEST_SERVER_INFO
   ],

   check => sub {
      my ( $alice, $bob, $test_server_info ) = @_;
      my $room_id;

      my $name = "Test Name";

      setup_push( $alice, $bob, $test_server_info, "/alice_push" )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $bob, $room_id,
            type    => "m.room.name",
            content => { name => $name },
         );
      })->then( sub {
         check_received_push_with_name( $bob, $room_id, "/alice_push", $name )
      });
   };

test "Rooms with canonical alias are correctly named in pushed",
   requires => [
      local_user_fixtures( 2, with_events => 0 ), room_alias_fixture(),
      $main::TEST_SERVER_INFO
   ],

   check => sub {
      my ( $alice, $bob, $room_alias, $test_server_info ) = @_;
      my $room_id;

      setup_push( $alice, $bob, $test_server_info, "/alice_push" )
      ->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $bob,
            method => "PUT",
            uri    => "/r0/directory/room/$room_alias",

            content => { room_id => $room_id },
         )
      })->then( sub {
         matrix_put_room_state( $bob, $room_id,
            type    => "m.room.canonical_alias",
            content => { alias => $room_alias },
         );
      })->then( sub {
         check_received_push_with_name( $bob, $room_id, "/alice_push", $room_alias )
      });
   };

test "Rooms with many users are correctly pushed",
   requires => [
      local_user_fixtures( 3, with_events => 0 ), room_alias_fixture(),
      $main::TEST_SERVER_INFO
   ],

   check => sub {
      my ( $alice, $bob, $charlie, $room_alias, $test_server_info ) = @_;
      my $room_id;

      my $name = "Test Name";

      setup_push( $alice, $bob, $test_server_info, "/alice_push" )
      ->then( sub {
         ($room_id) = @_;

         matrix_put_room_state($bob, $room_id,
             type    => "m.room.name",
             content => { name => $name },
         );
      })->then( sub {
         matrix_join_room( $charlie, $room_id)
      })->then( sub {
         do_request_json_for( $bob,
            method => "PUT",
            uri    => "/r0/directory/room/$room_alias",

            content => { room_id => $room_id },
         )
      })->then( sub {
         check_received_push_with_name( $bob, $room_id, "/alice_push", $name )
      });
   };

test "Don't get pushed for rooms you've muted",
   requires => [
      local_user_fixtures( 2, with_events => 0 ), $main::TEST_SERVER_INFO
   ],

   check => sub {
      my ( $alice, $bob, $test_server_info ) = @_;
      my $room_id;

      # The idea is to set up push, send a message "1", then disable push,
      # send "2" then enable and send "3", and assert that only messages 1 and 3
      # are received by push. This is because its "impossible" to test for the
      # absence of second push without doing a third.

      setup_push( $alice, $bob, $test_server_info, "/alice_push" )
      ->then( sub {
         ( $room_id ) = @_;

         log_if_fail "room_id", $room_id;

         Future->needs_all(
            await_http_request( "/alice_push", sub {
               my ( $request ) = @_;

               log_if_fail "Got /alice_push request";

               # Respond to all requests, even if we filiter them out
               $request->respond_json( {} );

               my $body = $request->body_from_json;

               return unless $body->{notification}{type};
               return unless $body->{notification}{type} eq "m.room.message";
               return 1;
            }),
            matrix_send_room_text_message( $bob, $room_id,
               body => "Initial Message",
            ),
         )
      })->then( sub {
         my ( $request ) = @_;
         my $body = $request->body_from_json;

         log_if_fail "Message push request body", $body;

         assert_json_keys( my $notification = $body->{notification}, qw(
            id room_id type sender content devices counts
         ));

         assert_eq( $notification->{room_id}, $room_id, "room_id");
         assert_eq( $notification->{sender}, $bob->user_id, "sender");
         assert_eq( $notification->{content}{body}, "Initial Message", "message");

         Future->done(1);
      })->then( sub {
         do_request_json_for( $alice,
            method  => "PUT",
            uri     => "/r0/pushrules/global/room/$room_id",
            content => { actions => [ "dont_notify" ] },
         )
      })->then( sub {
         # We now test that after having set dont_notify above we won't get any
         # more pushes in that room, unless they're mentions.
         #
         # We do this by sending two messages, one which isn't a mention and one
         # which is, and then asserting that we only see the mention. Since
         # setting push rules can take a few moments to take effect, we may need
         # to retry a few times before we see the expected behaviour.
         retry_until_success {
            my $push_count = 0;  # Counts the number of pushes we've seen in this loop

            Future->needs_all(
               await_http_request( "/alice_push", sub {
                  my ( $request ) = @_;
                  my $body = $request->body_from_json;

                  # Respond to all requests, even if we filiter them out
                  $request->respond_json( {} );

                  log_if_fail "Received push", $body;

                  return unless $body->{notification}{type};
                  return unless $body->{notification}{type} eq "m.room.message";

                  $push_count += 1;

                  # Either: 1) we get the first message we send, i.e. the one
                  # that we didn't expect to get pushed, so we continue waiting,
                  # or 2) this was the second message so we stop waiting.
                  return unless $body->{notification}{content}{expect} eq JSON::true;

                  return 1;
               }),
               matrix_send_room_message( $bob, $room_id,
                  content => {
                     msgtype => "m.text",
                     body    => "First message (Should not be pushed)",
                     expect  => JSON::false,  # This shouldn't be pushed
                  }
               )->then( sub {
                  matrix_send_room_message( $bob, $room_id,
                     content => {
                        msgtype => "m.text",
                        body    => "Second message - " . $alice->user_id,
                        expect  => JSON::true,  # This should be pushed
                     }
                  )
               }),
            )->then( sub {
               my ( $request ) = @_;

               assert_eq( $push_count, 1 );

               Future->done( $request );
            })
         }
      })->then( sub {
         my ( $request ) = @_;
         my $body = $request->body_from_json;

         log_if_fail "Message push request body", $body;

         assert_json_keys( my $notification = $body->{notification}, qw(
            id room_id type sender content devices counts
         ));

         assert_eq( $notification->{room_id}, $room_id, "room_id");
         assert_eq( $notification->{sender}, $bob->user_id, "sender");
         assert_eq( $notification->{content}{body}, "Second message - " . $alice->user_id, "message");

         Future->done(1);
      });
   };

test "Rejected events are not pushed",
   requires => [
      federated_rooms_fixture(),
      local_user_fixture(),
      $main::OUTBOUND_CLIENT,
      $main::TEST_SERVER_INFO,
   ],

   do => sub {
      my ( $alice, $sytest_user_id, $room, $bob, $outbound_client, $test_server_info ) = @_;

      # first we send an event from a different user (which should be rejected):
      my $rejected_event = $room->create_and_insert_event(
         type => "m.room.message",
         sender  => '@fakeuser:' . $outbound_client->server_name,
         content => { body => "rejected" },
      );

      my $regular_event = $room->create_and_insert_event(
         type => "m.room.message",
         sender  => $sytest_user_id,
         content => { body => "Hello" },
      );

      log_if_fail "Rejected event " . $room->id_for_event( $rejected_event );
      log_if_fail "Regular event " . $room->id_for_event( $regular_event );

      matrix_set_pusher(
         $alice, $test_server_info->client_location . "/alice_push",
      )->then( sub {
         # we need a second local user in the room, so that we can test if
         # alice's pusher is active.
         matrix_join_room( $bob, $room->room_id );
      })->then( sub {
         wait_for_pusher_to_work( $bob, $room->room_id, "/alice_push" );
      })->then( sub {
         Future->needs_all(
            # we send the rejected event first, and then the regular event, and
            # check that we don't get a push for the rejeced event before the
            # regular event.
            $outbound_client->send_event(
               event => $rejected_event,
               destination => $alice->server_name,
            )->then( sub {
               $outbound_client->send_event(
                  event => $regular_event,
                  destination => $alice->server_name,
               );
            }),

            await_http_request( "/alice_push" )->then( sub {
               my ( $request ) = @_;
               my $body = $request->body_from_json;
               $request->respond_json( {} );

               log_if_fail "Received push", $body;

               assert_eq( $body->{notification}{event_id}, $room->id_for_event( $regular_event ) );
               Future->done();
            }),
         );
      });
   };
