test "/context/ on joined room works",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_send_room_text_message( $user, $room_id,
         body => "hello, world",
      )->then( sub {
         my ( $event_id ) = @_;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/context/$event_id",
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( state event ) );

         Future->done( 1 )
      });
   };

test "/context/ on non world readable room does not work",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   check => sub {
      my ( $user, $room_id, $other_user ) = @_;

      matrix_send_room_text_message( $user, $room_id,
         body => "hello, world",
      )->then( sub {
         my ( $event_id ) = @_;

         do_request_json_for( $other_user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/context/$event_id",
         );
      })->main::expect_http_403;
   };
