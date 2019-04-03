my $creator_fixture = local_user_fixture();

test "Users cannot kick users from a room they are not in",
   requires => [ $creator_fixture,
                 magic_room_fixture( requires_users => [ $creator_fixture ] )
               ],

   do => sub {
      my ( $creator, $room_id ) = @_;
      my $fake_user_id = '@bob:example.com';

      do_request_json_for( $creator,
         method => "POST",
         uri    => "/r0/rooms/$room_id/kick",

         content => { user_id => $fake_user_id, reason => "testing" },
      )->main::expect_http_403; # 403 for kicking a user who isn't in the room
   };

my $kicked_user_fixture = local_user_fixture();

test "Users cannot kick users who have already left a room",
    requires => [ $creator_fixture, $kicked_user_fixture,
                    magic_room_fixture( requires_users => [ $creator_fixture, $kicked_user_fixture ] )
                ],

    do => sub {
        my ( $creator, $kicked_user, $room_id ) = @_;

        do_request_json_for( $creator,
           method => "POST",
           uri    => "/r0/rooms/$room_id/kick",

           content => { user_id => $kicked_user->user_id, reason => "testing" },
        )->then( sub {
            retry_until_success {
                matrix_get_room_state( $creator, $room_id,
                    type      => "m.room.member",
                    state_key => $kicked_user->user_id,
                )
            }
        })->then( sub {
            my ( $body ) = @_;
            $body->{membership} eq "leave" or
                die "Expected kicked user membership to be 'leave'";

            do_request_json_for( $creator,
                method => "POST",
                uri    => "/r0/rooms/$room_id/kick",

                content => { user_id => $kicked_user->user_id, reason => "testing" },
            )->main::expect_http_403; # 403 for kicking a user who isn't in the room anymore
        })
   };
