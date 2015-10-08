sub make_room_and_message
{
   my ( $users, $sender ) = @_;

   my $room_id;
   matrix_create_and_join_room( $users )->then( sub {
      ( $room_id ) = @_;

      matrix_send_room_message( $sender, $room_id,
         content => { msgtype => "m.message", body => "orangutans are not monkeys" },
      )
   })->then( sub {
      my ( $event_id ) = @_;

      return Future->done( $room_id, $event_id );
   });
}

test "POST /rooms/:room_id/redact/:event_id as power user redacts message",
   requires => [qw( local_users
                    can_send_message )],

   do => sub {
      my ( $local_users ) = @_;
      # 100 power level
      my $room_creator   = $local_users->[0];
      # 0 power level
      my $test_user = $local_users->[1];

      make_room_and_message( $local_users, $test_user )
      ->then( sub {
         my ( $room_id, $to_redact ) = @_;

         do_request_json_for( $room_creator,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/redact/$to_redact",
            content => {},
         );
      });
   };

test "POST /rooms/:room_id/redact/:event_id as original message sender redacts message",
   requires => [qw( local_users
                    can_send_message )],

   do => sub {
      my ( $local_users ) = @_;
      # 0 power level
      my $test_user = $local_users->[1];

      make_room_and_message( $local_users, $test_user )
      ->then( sub {
         my ( $room_id, $to_redact ) = @_;

         do_request_json_for( $test_user,
               method => "POST",
               uri    => "/api/v1/rooms/$room_id/redact/$to_redact",
               content => {},
         );
      });
   };

test "POST /rooms/:room_id/redact/:event_id as random user does not redact message",
   requires => [qw( local_users
                    can_send_message )],

   do => sub {
      my ( $local_users ) = @_;
      # Both have 0 power level
      my $test_user = $local_users->[1];
      my $other_test_user = $local_users->[2];

      make_room_and_message( $local_users, $test_user )
      ->then( sub {
         my ( $room_id, $to_redact ) = @_;

         do_request_json_for( $other_test_user,
               method => "POST",
               uri    => "/api/v1/rooms/$room_id/redact/$to_redact",
               content => {},
         )
      })->main::expect_http_403;
   };
