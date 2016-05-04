test "Can report event",
   requires => do {
      my $local_user1_fixture = local_user_fixture();
      my $local_user2_fixture = local_user_fixture();

      my $room_fixture = magic_room_fixture(
         requires_users => [ $local_user1_fixture, $local_user2_fixture ],
      );

      [
         $local_user1_fixture, $local_user2_fixture,
         $room_fixture, qw( can_send_message )
      ]
   },

   do => sub {
      my ( $user1, $user2, $room_id ) = @_;

      my $user;
      matrix_send_room_message( $user2, $room_id,
         content => { msgtype => "m.text", body => "Message" }
      )->then( sub {
         my ( $event_id ) = @_;

         do_request_json_for( $user1,
            method  => "POST",
            uri     => "/r0/rooms/$room_id/report/$event_id",
            content => {
               reason => "Because I said so",
            }
         )
      })
   };
