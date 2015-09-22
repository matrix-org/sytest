multi_test "Check that event streams started after a client joined a room work (SYT-1)",
   requires => [qw(
      first_api_client register_new_user_without_events do_request_json_for await_event_for flush_events_for
      can_register can_create_private_room
   )],

   do => sub {
      my ( $http, $register_new_user_without_events, $do_request_json_for, $await_event_for, $flush_events_for ) = @_;

      my $alice;
      my $room;

      $register_new_user_without_events->( $http, "90jira-SYT-1_alice" )->then( sub {
         ( $alice ) = @_;
         pass "Registered user";

         # Have Alice create a new private room
         $do_request_json_for->( $alice,
            method => "POST",
            uri     => "/api/v1/createRoom",
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
            method  => "POST",
            uri     => "/api/v1/rooms/$room->{room_id}/send/m.room.message",

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
         });
      })->then( sub {
         pass "Alice saw her message";
         Future->done(1);
      });
   };
