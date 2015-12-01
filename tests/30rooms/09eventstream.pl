multi_test "Check that event streams started after a client joined a room work (SYT-1)",
   requires => [ local_user_fixture( with_events => 0 ),
      qw( can_create_private_room can_send_message )
   ],

   do => sub {
      my ( $alice ) = @_;

      my $room_id;

      # Have Alice create a new private room
      matrix_create_room( $alice,
         visibility => "private",
      )->SyTest::pass_on_done( "Created a room" )
      ->then( sub {
         ( $room_id ) = @_;
         # Now that we've joined a room, flush the event stream to get
         # a stream token from before we send a message.
         flush_events_for( $alice );
      })->then( sub {
         # Alice sends a message
         matrix_send_room_message( $alice, $room_id,
            content => {
               msgtype => "m.message",
               body    => "Room message for 90jira-SYT-1"
            },
         )
      })->then( sub {
         my ( $event_id ) = @_;

         # Wait for the message we just sent.
         await_event_for( $alice, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{event_id} eq $event_id;
            return 1;
         })->SyTest::pass_on_done( "Alice saw her message" )
      })->then_done(1);
   };
