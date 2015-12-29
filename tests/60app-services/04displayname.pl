
multi_test "AS-ghosted users can set their display name",
   requires => [ $main::AS_USER,
                qw( can_receive_room_message_locally can_send_message )],

   do => sub {
      my ( $as_user ) = @_;

      my $ghost_id = "\@astest-bob:localhost:8001";

      do_request_json_for( $as_user,
         method => "POST",
         uri => "/api/v1/createRoom",
         params => { user_id => $ghost_id },
         content => {},
      )->then( sub {
         my ( $body ) = @_;

         my $room_id = $body->{room_id};

         do_request_json_for( $as_user,
            method => "PUT",
            uri => "/api/v1/profile/$ghost_id/displayname",
            params => { user_id => $ghost_id },
            content => { displayname => "http://something" },
         );
      });
   };
