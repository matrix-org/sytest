my ( $user1, $user2 ) = prepare_local_users( 2 );

multi_test "Left room members do not cause problems for presence",
   requires => [qw( can_room_initial_sync )],

   do => sub {
      my $room_id;

      matrix_create_and_join_room( [ $user1, $user2 ] )
         ->SyTest::pass_on_done( "Created room" )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_leave_room( $user2, $room_id )
            ->SyTest::pass_on_done( "Left room" )
      })->then( sub {

         do_request_json_for( $user1,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/initialSync",
         )
      })->then( sub {
         my ( $body ) = @_;

         # TODO(paul):
         #   Impossible currently for this unit test to detect it, but the
         #   log should hopefully *not* contain a message like this:
         #
         #      synapse.handlers.message - 395 - WARNING -  - Failed to get member presence of u'@SYN-202-user2:localhost:8001'

         Future->done(1);
      });
   };
