foreach my $i (
   [ "Anonymous", sub { anonymous_user_fixture() } ],
   [ "Real", sub { local_user_fixture() } ]
) {
   my ( $name, $fixture ) = @$i;

   test(
      "$name user can call /events on another world_readable room (SYN-606)",
      requires => [ $fixture->( with_events => 0 ),
                    local_user_fixture( with_events => 0 ) ],

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
            Future->needs_all(
               matrix_send_room_text_message( $user, $room_id1, body => "moose" ),
               await_event_not_history_visibility_or_presence_for( $nonjoined_user, $room_id1, [] ),
            );
         })->then( sub {
            matrix_initialsync_room( $nonjoined_user, $room_id2 )
         })->then( sub {
            Future->needs_all(
               delay( 0.1 )->then( sub {
                  matrix_send_room_text_message( $user, $room_id2, body => "mice" );
               }),

               await_event_not_history_visibility_or_presence_for( $nonjoined_user, $room_id2, [] )
               ->then( sub {
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
