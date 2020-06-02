foreach my $i (
   [ "Guest", sub { guest_user_fixture() } ],
   [ "Real", sub { local_user_fixture() } ]
) {
   my ( $name, $fixture ) = @$i;

   test(
      "$name user can call /events on another world_readable room (SYN-606)",
      requires => [ $fixture->(),  local_user_fixture(), qw ( deprecated_endpoints ) ],

      do => sub {
         my ( $nonjoined_user, $user ) = @_;

         my ( $room_id1, $room_id2 );

         Future->needs_all(
            matrix_create_and_join_room( [ $user ] ),
            matrix_create_and_join_room( [ $user ] ),
         )->then( sub {
            ( $room_id1, $room_id2 ) = @_;

            Future->needs_all(
               matrix_set_room_history_visibility( $user, $room_id1, "world_readable" ),
               matrix_set_room_history_visibility( $user, $room_id2, "world_readable" ),
            )
         })->then( sub {
            matrix_initialsync_room( $nonjoined_user, $room_id1 )
         })->then( sub {
            my ( $body ) = @_;

            # We need to manually handle the from tokens here as the await_event*
            # methods may otherwise reuse results from an /events call that did
            # not include the specified room (due to the user not being joined to
            # it). This could cause the event to not be found.
            # I.e. there is a race where we send a message, the background /events
            # stream streams past the message, and then /events stream triggered by
            # await_event_* (which *does* include the room_id) starts streaming
            # from *after* the message. Hence the event is neither in the cache
            # nor in the live event stream.
            my $from_token = $body->{messages}{end};

            Future->needs_all(
               matrix_send_room_text_message( $user, $room_id1, body => "moose" ),
               await_event_not_history_visibility_or_presence_for( $nonjoined_user, $room_id1, [],
                  from => $from_token,
               ),
            );
         })->then( sub {
            matrix_initialsync_room( $nonjoined_user, $room_id2 )
         })->then( sub {
            my ( $body ) = @_;

            my $from_token = $body->{messages}{end};

            Future->needs_all(
               matrix_send_room_text_message( $user, $room_id2, body => "mice" ),
               await_event_not_history_visibility_or_presence_for( $nonjoined_user, $room_id2, [],
                  from => $from_token,
               )->then( sub {
                  my ( $event ) = @_;

                  assert_json_keys( $event, qw( content ) );
                  my $content = $event->{content};
                  assert_json_keys( $content, qw( body ) );
                  assert_eq( $content->{body}, "mice" );

                  Future->done( 1 );
               }),
            );
         });
      },
   );
}
