multi_test "Check that event streams started after a client joined a room work (SYT-1)",
   requires => [qw(
      first_api_client register_new_user_without_events make_test_room
      do_request_json_for await_event_for flush_events_for

      can_register can_create_private_room
   )],

   do => sub {
      my (
         $http, $register_new_user_without_events, $make_test_room,
         $do_request_json_for, $await_event_for, $flush_events_for,
      ) = @_;

      my $alice;
      my $room_id;

      $register_new_user_without_events->( $http, "90jira-SYT-1_alice" )
         ->SyTest::pass_on_done( "Registered user" )
      ->then( sub {
         ( $alice ) = @_;

         # Have Alice create a new private room
         $make_test_room->( [ $alice ],
            visibility => "private",
         )->SyTest::pass_on_done( "Created a room" )
      })->then( sub {
         ( $room_id ) = @_;
         # Now that we've joined a room, flush the event stream to get
         # a stream token from before we send a message.
         $flush_events_for->( $alice );
      })->then( sub {
         # Alice sends a message
         $do_request_json_for->( $alice,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/send/m.room.message",

            content => {
               msgtype => "m.message",
               body    => "Room message for 90jira-SYT-1"
            },
         )
      })->then( sub {
         my ( $body ) = @_;
         my $event_id = $body->{event_id};

         # Wait for the message we just sent.
         $await_event_for->( $alice, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{event_id} eq $event_id;
            return 1;
         })->SyTest::pass_on_done( "Alice saw her message" )
      })->then_done(1);
   };
