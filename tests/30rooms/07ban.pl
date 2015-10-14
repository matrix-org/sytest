my $creator_preparer = local_user_preparer();

my $banned_user_preparer = local_user_preparer();

test "Banned user is kicked and may not rejoin",
   requires => [ $creator_preparer, $banned_user_preparer,
                     room_preparer( requires_users => [ $creator_preparer, $banned_user_preparer ] ),
                qw( can_ban_room )],

   do => sub {
      my ( $creator, $banned_user, $room_id ) = @_;

      do_request_json_for( $creator,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/ban",

         content => { user_id => $banned_user->user_id, reason => "testing" },
      )->then( sub {
         matrix_get_room_state( $creator, $room_id,
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
