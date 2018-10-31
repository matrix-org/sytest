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

test "/event/ does not allow access to events before the user joined",
   requires => [
      local_user_and_room_fixtures(),
      local_user_fixture(),
   ],

   check => sub {
      my ( $user, $room_id, $other_user ) = @_;

      my ( $event_id_1, $event_id_2 );

      matrix_set_room_history_visibility(
         $user, $room_id, "joined",
      )->then( sub {
         matrix_invite_user_to_room(
            $user, $other_user, $room_id,
         );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id,
            body => "before join",
         );
      })->then( sub {
         ( $event_id_1 ) = @_;

         matrix_join_room_synced( $other_user, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id,
            body => "after join",
         );
      })->then( sub {
         ( $event_id_2 ) = @_;

         # we shouldn't be able to get the event before we joined.
         do_request_json_for( $other_user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/event/$event_id_1",
         );
      })->main::expect_http_403->then( sub {
         # we should be able to get the event after we joined.
         do_request_json_for( $other_user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/event/$event_id_2",
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( content type room_id sender event_id unsigned ) );
         assert_eq( $body->{event_id}, $event_id_2, "event id" );
         assert_eq( $body->{content}->{body}, "after join", "body" );

         Future->done(1);
      });
   };
