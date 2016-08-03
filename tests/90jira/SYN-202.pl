multi_test "Left room members do not cause problems for presence",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_room_initial_sync )],

   do => sub {
      my ( $user1, $user2 ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $user1, $user2 ] )
         ->SyTest::pass_on_done( "Created room" )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_leave_room( $user2, $room_id )
            ->SyTest::pass_on_done( "Left room" )
      })->then( sub {

         matrix_initialsync_room( $user1, $room_id );
      })->then( sub {
         my ( $body ) = @_;

         # TODO(paul):
         #   Impossible currently for this unit test to detect it, but the
         #   log should hopefully *not* contain a message like this:
         #
         #      synapse.handlers.message - 395 - WARNING -  - Failed to get member presence of u'@SYN-202-user2:$BIND_HOST:8001'

         Future->done(1);
      });
   };
