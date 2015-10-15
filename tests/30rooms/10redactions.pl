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
   requires => [ local_user_preparers( 2 ),
                 qw( can_send_message )],

   do => sub {
      my ( $creator, $sender ) = @_;

      make_room_and_message( [ $creator, $sender ], $sender )
      ->then( sub {
         my ( $room_id, $to_redact ) = @_;

         do_request_json_for( $creator,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/redact/$to_redact",
            content => {},
         );
      });
   };

test "POST /rooms/:room_id/redact/:event_id as original message sender redacts message",
   requires => [ local_user_preparers( 2 ),
                 qw( can_send_message )],

   do => sub {
      my ( $creator, $sender ) = @_;

      make_room_and_message( [ $creator, $sender ], $sender )
      ->then( sub {
         my ( $room_id, $to_redact ) = @_;

         do_request_json_for( $sender,
               method => "POST",
               uri    => "/api/v1/rooms/$room_id/redact/$to_redact",
               content => {},
         );
      });
   };

test "POST /rooms/:room_id/redact/:event_id as random user does not redact message",
   requires => [ local_user_preparers( 3 ),
                 qw( can_send_message )],

   do => sub {
      my ( $creator, $sender, $redactor ) = @_;

      make_room_and_message( [ $creator, $sender, $redactor ], $sender )
      ->then( sub {
         my ( $room_id, $to_redact ) = @_;

         do_request_json_for( $redactor,
               method => "POST",
               uri    => "/api/v1/rooms/$room_id/redact/$to_redact",
               content => {},
         )
      })->main::expect_http_403;
   };
