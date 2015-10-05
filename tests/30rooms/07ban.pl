test "Banned user is kicked and may not rejoin",
   requires => [qw( user more_users
                    can_ban_room )],

   do => sub {
      my ( $user, $more_users ) = @_;
      my $banned_user = $more_users->[0];

      my $room_id;

      matrix_create_room( $user )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $banned_user, $room_id )
      })->then( sub {
         do_request_json_for( $user,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/ban",

            content => { user_id => $banned_user->user_id, reason => "testing" },
         );
      })->then( sub {
         matrix_get_room_state( $user, $room_id,
            type      => "m.room.member",
            state_key => $banned_user->user_id,
         )
      })->then( sub {
         my ( $body ) = @_;
         $body->{membership} eq "ban" or
            die "Expected banned user membership to be 'ban'";

         matrix_join_room( $banned_user, $room_id )
      })->main::expect_http_403;
   };
