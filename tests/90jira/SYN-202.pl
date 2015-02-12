multi_test "Left room members do not cause problems for presence",
   requires => [qw( first_http_client do_request_json_for more_users
                    can_create_private_room can_leave_room can_room_initial_sync )],

   do => sub {
      my ( $http, $do_request_json_for, $more_users ) = @_;
      my ( $user1, $user2 );
      my $room_id;

      # Register two users
      Future->needs_all(
         map {
            $http->do_request_json(
               method => "POST", uri => "/register",
               content => {
                  type     => "m.login.password",
                  user     => "SYN-202-$_",
                  password => "passwd"
               },
            )->then( sub { Future->done( $_[0] ) } )
         } qw( user1 user2 )
      )->then( sub {
         my ( $user1body, $user2body ) = @_;

         pass "Registered users";

         $user1 = User( $http, @{$user1body}{qw( user_id access_token )}, undef, [], undef );
         $user2 = User( $http, @{$user2body}{qw( user_id access_token )}, undef, [], undef );

         $do_request_json_for->( $user1,
            method => "POST",
            uri    => "/createRoom",

            content => { visibility => "public" },
         );
      })->then( sub {
         my ( $body ) = @_;

         pass "Created room";

         $room_id = $body->{room_id};

         $do_request_json_for->( $user2,
            method => "POST",
            uri    => "/rooms/$room_id/join",

            content => {},
         );
      })->then( sub {
         pass "Joined room";

         $do_request_json_for->( $user2,
            method => "POST",
            uri    => "/rooms/$room_id/leave",

            content => {},
         );
      })->then( sub {
         pass "Left room";

         $do_request_json_for->( $user1,
            method => "GET",
            uri    => "/rooms/$room_id/initialSync",
         )
      })->then( sub {
         my ( $body ) = @_;

         # TODO(paul):
         #   Impossible currently for this unit test to detect it, but the
         #   log should hopefully *not* contain a message like this:
         #
         #      synapse.handlers.message - 395 - WARNING -  - Failed to get member presence of u'@SYN-202-user2:localhost:8001'

         Future->done;
      });
   };
