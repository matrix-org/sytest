test "/event/ on joined room works",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_send_room_text_message( $user, $room_id,
         body => "hello, world",
      )->then( sub {
         my ( $event_id ) = @_;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/event/$event_id",
         )->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( content type room_id sender event_id unsigned ) );
            assert_eq( $body->{event_id}, $event_id, "event id" );
            assert_eq( $body->{room_id}, $room_id, "room id" );
            assert_eq( $body->{content}->{body}, "hello, world", "body" );

            Future->done( 1 );
         });
      });
   };

test "/event/ on non world readable room does not work",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   check => sub {
      my ( $user, $room_id, $other_user ) = @_;

      matrix_send_room_text_message( $user, $room_id,
         body => "hello, world",
      )->then( sub {
         my ( $event_id ) = @_;

         do_request_json_for( $other_user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/event/$event_id",
         );
      })->main::expect_http_403;
   };
