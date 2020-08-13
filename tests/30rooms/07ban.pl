my $creator_fixture = local_user_fixture();

my $banned_user_fixture = local_user_fixture();

test "Banned user is kicked and may not rejoin until unbanned",
   requires => [ $creator_fixture, $banned_user_fixture,
                     magic_room_fixture( requires_users => [ $creator_fixture, $banned_user_fixture ] ),
                qw( can_ban_room )],

   do => sub {
      my ( $creator, $banned_user, $room_id ) = @_;

      do_request_json_for( $creator,
         method => "POST",
         uri    => "/r0/rooms/$room_id/ban",

         content => { user_id => $banned_user->user_id, reason => "testing" },
      )->then( sub {
         retry_until_success {
            matrix_get_room_state( $creator, $room_id,
               type      => "m.room.member",
               state_key => $banned_user->user_id,
            )->then( sub {
               my ( $body ) = @_;
               $body->{membership} eq "ban" or
                  die "Expected banned user membership to be 'ban'";

               Future->done( 1 )
            })
         }
      })->then( sub {
         matrix_join_room( $banned_user, $room_id )
            ->main::expect_http_403;  # Must be unbanned first
      })->then( sub {
         do_request_json_for( $creator,
            method => "POST",
            uri    => "/r0/rooms/$room_id/invite",

            content => { user_id => $banned_user->user_id },
         )->main::expect_http_403;  # Must be unbanned first
      })->then( sub {
         do_request_json_for( $creator,
            method => "POST",
            uri    => "/r0/rooms/$room_id/kick",

            content => { user_id => $banned_user->user_id },
         )->main::expect_http_403;  # Must be unbanned first
      })->then( sub {
         do_request_json_for( $creator,
            method => "POST",
            uri    => "/r0/rooms/$room_id/unban",

            content => { user_id => $banned_user->user_id },
         );
      })->then( sub {
         do_request_json_for( $banned_user,
            method => "POST",
            uri    => "/r0/rooms/$room_id/join",

            content => {},
         );
      })
   };


my $banned_remote_user_fixture = remote_user_fixture();

test "Remote banned user is kicked and may not rejoin until unbanned",
   requires => [ $creator_fixture, $banned_remote_user_fixture,
                     magic_room_fixture( requires_users => [ $creator_fixture, $banned_remote_user_fixture ] ),
                qw( can_ban_room )],

   do => sub {
      my ( $creator, $banned_user, $room_id ) = @_;

      do_request_json_for( $creator,
         method => "POST",
         uri    => "/r0/rooms/$room_id/ban",

         content => { user_id => $banned_user->user_id, reason => "testing" },
      )->then( sub {
         retry_until_success {
            matrix_get_room_state( $creator, $room_id,
               type      => "m.room.member",
               state_key => $banned_user->user_id,
            )->then( sub {
               my ( $body ) = @_;
               $body->{membership} eq "ban" or
                  die "Expected banned user membership to be 'ban'";

               Future->done( 1 )
            })
         }
      })->then( sub {
         repeat_until_true {
            matrix_get_room_state( $banned_user, $room_id,
               type      => "m.room.member",
               state_key => $banned_user->user_id,
            )->main::check_http_code(
               403 => "ok",
               200 => "redo",
            );
         };
      })->then( sub {
         # Must be unbanned first
         matrix_join_room( $banned_user, $room_id )->main::check_http_code(
            403 => "ok",
            200 => "redo",
         );
      })->then( sub {
         # Must be unbanned first
         do_request_json_for( $creator,
            method => "POST",
            uri    => "/r0/rooms/$room_id/invite",

            content => { user_id => $banned_user->user_id },
         )->main::check_http_code(
            403 => "ok",
            200 => "redo",
         );
      })->then( sub {
         # Must be unbanned first
         do_request_json_for( $creator,
            method => "POST",
            uri    => "/r0/rooms/$room_id/kick",

            content => { user_id => $banned_user->user_id },
         )->main::check_http_code(
            403 => "ok",
            200 => "redo",
         );
      });
   };
