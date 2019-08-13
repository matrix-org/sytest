# note that there are happy-path tests for typing over federation in tests/30rooms/20typing.pl.

test "Inbound federation rejects typing notifications from wrong remote",
   requires => [
      $main::OUTBOUND_CLIENT,
      $main::HOMESERVER_INFO[0],
      local_user_and_room_fixtures(),
      federation_user_id_fixture(),
   ],

   do => sub {
      my ( $outbound_client, $info, $creator, $room_id, $user_id ) = @_;

      my $local_server_name = $info->server_name;

      $outbound_client->join_room(
         server_name => $local_server_name,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         # First we send a typing notif from a user that isn't ours.
         $outbound_client->send_edu(
            edu_type    => "m.typing",
            destination => $local_server_name,
            content     => {
               room_id => $room_id,
               user_id => $creator->user_id,
               typing  => JSON::true,
            },
         );
      })->then( sub {
         # Then we send one for a user that is ours.
         $outbound_client->send_edu(
            edu_type    => "m.typing",
            destination => $local_server_name,
            content     => {
               room_id => $room_id,
               user_id => $user_id,
               typing  => JSON::true,
            },
         );
      })->then( sub {
         # The sync should only contain the second typing notif, since the first
         # should have been dropped.
         await_sync( $creator, check => sub {
            my ( $body ) = @_;

            sync_room_contains( $body, $room_id, "ephemeral", sub {
               my ( $edu ) = @_;

               log_if_fail "received edu", $edu;

               return unless $edu->{type} eq "m.typing";

               my @users = @{ $edu->{content}->{user_ids} };

               # Check for bad user
               die "Found typing notif that should have been rejected"
                  if any { $_ ne $user_id } @users;

               # Stop waiting when we find the good user (ie, we have a non-empty list)
               return scalar @users;
            })
         })
      });
   };
