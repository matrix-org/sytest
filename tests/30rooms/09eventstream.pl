use Future::Utils qw( repeat try_repeat );


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


test "Event stream catches up fully after many messages",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_send_message )],

   do => sub {
      my ( $user ) = @_;
      my ( $room_id, @expected_event_ids );

      matrix_create_room( $user,
        visibility => "private",
      )
      ->then( sub {
         ( $room_id ) = @_;

         flush_events_for( $user )
      })
      ->then( sub {
         repeat( sub {
            my ( $msgnum ) = @_;

            matrix_send_room_text_message( $user, $room_id,
               body => "Message number $msgnum"
            )
            ->on_done( sub {
               push @expected_event_ids, @_;
            })
         }, foreach => [ 0 .. 19 ] )
      })
      ->then( sub {
         try_repeat( sub {
            matrix_get_events( $user,
               from    => $user->eventstream_token,
               timeout => 500,
               limit   => 5,
            )->on_done( sub {
               my ( $body ) = @_;
               my ( $expected_id );
               my ( @events ) = @{ $body->{chunk} };

               $user->eventstream_token = $body->{end};

               log_if_fail "Events", @events;

               foreach my $event ( @events ) {
                  if ( $event->{type} eq 'm.room.message' ) {
                     $expected_id = shift @expected_event_ids;

                     assert_eq( $event->{event_id}, $expected_id,
                        'Unexpected or out of order event'
                     );
                  }
               }
            })
         }, foreach => [ 0 .. 10 ], while => sub {
            @expected_event_ids > 0
         } )
      })->then( sub {
         @expected_event_ids == 0 or die "Did not see all events.";

         Future->done(1);
      });
   };
