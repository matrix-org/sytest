multi_test "Left room members do not cause problems for presence",
   requires => [qw( first_api_client more_users
                    can_room_initial_sync )],

   await => sub {
      my ( $http, $more_users ) = @_;
      my ( $user1, $user2 );
      my $room_id;

      # Register two users
      Future->needs_all(
         map { matrix_register_user( $http ) } 1, 2
      )->SyTest::pass_on_done( "Registered users" )
      ->then( sub {
         ( $user1, $user2 ) = @_;

         matrix_create_and_join_room( [ $user1, $user2 ] )
            ->SyTest::pass_on_done( "Created room" )
      })->then( sub {
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
