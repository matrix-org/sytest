multi_test "Left room members do not cause problems for presence",
   requires => [qw( register_new_user first_api_client make_test_room do_request_json_for more_users
                    can_leave_room can_room_initial_sync )],

   await => sub {
      my ( $register_new_user, $http, $make_test_room, $do_request_json_for, $more_users ) = @_;
      my ( $user1, $user2 );
      my $room_id;

      # Register two users
      Future->needs_all(
         map { $register_new_user->( $http, "SYN-202-$_" ) } qw( user1 user2 )
      )->SyTest::pass_on_done( "Registered users" )
      ->then( sub {
         ( $user1, $user2 ) = @_;

         $make_test_room->( [ $user1, $user2 ] )
            ->SyTest::pass_on_done( "Created room" )
      })->then( sub {
         ( $room_id ) = @_;

         $do_request_json_for->( $user2,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/leave",

            content => {},
         )->SyTest::pass_on_done( "Left room" )
      })->then( sub {

         $do_request_json_for->( $user1,
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
