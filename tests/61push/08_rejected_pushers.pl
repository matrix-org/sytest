sub create_pusher
{
   my ( $user, $app_id, $push_key, $url ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/r0/pushers/set",
      content => {
         profile_tag         => "tag1",
         kind                => "http",
         app_id              => $app_id,
         app_display_name    => "sytest_display_name",
         device_display_name => "device_display_name",
         pushkey             => $push_key,
         lang                => "en",
         data                => { url => $url },
      },
   );
}

sub wait_for_push
{
   my ( $path, $response ) = @_;

   await_http_request( $path, sub {
     my ( $request ) = @_;
     my $body = $request->body_from_json;

     return unless $body->{notification}{type};
     return unless $body->{notification}{type} eq "m.room.message";
     return 1;
   })->then( sub {
      my ( $request ) = @_;

      $request->respond_json( $response // {} );
      Future->done( $request );
   });
}

multi_test "Test that rejected pushers are removed.",
   requires => [
      local_user_fixtures( 2, with_events => 0 ),
      $main::TEST_SERVER_INFO,
   ],

   do => sub {
      my ( $alice, $bob, $test_server_info ) = @_;

      my $room_id;

      my $url = $test_server_info->client_location . "/alice_push";

      matrix_create_room( $alice, visibility => "private" )->then( sub {
         ( $room_id ) = @_;
         matrix_invite_user_to_room( $alice, $bob, $room_id ),
      })->then( sub {
         matrix_join_room( $bob, $room_id);
      })->then( sub {
         matrix_send_room_text_message(
            $bob, $room_id, body => "message"
         );
      })->then( sub {
         my ( $event_id ) = @_;

         # Set a read receipt so that we pushed for the subsequent messages.
         matrix_advance_room_receipt( $alice, $room_id,
            "m.read" => $event_id
         );
      })->then( sub {
         create_pusher( $alice, "sytest", "key_1", "$url/1" )
            ->SyTest::pass_on_done( "Alice's pusher 1 created" );
      })->then( sub {
         create_pusher( $alice, "sytest", "key_2", "$url/2" )
            ->SyTest::pass_on_done( "Alice's pusher 2 created" );
      })->then( sub {
         do_request_json_for( $alice,
              method  => "GET",
              uri     => "/r0/pushers",
         )->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( pushers ) );
            @{ $body->{pushers} } == 2 or die "Expected two pushers";

            Future->done(1);
         });
      })->then( sub {
         Future->needs_all(
            wait_for_push( "/alice_push/1",  { rejected => [ "key_1" ] } ),
            wait_for_push( "/alice_push/2" ),
            matrix_send_room_text_message( $bob, $room_id, body => "message" )
               ->SyTest::pass_on_done( "Message 1 Sent" ),
         )->SyTest::pass_on_done( "Message 1 Pushed" );
      })->then( sub {
         # Send another push message to increase the chance that previous
         # messages have been processed.
         Future->needs_all(
            wait_for_push( "/alice_push/2" ),
            matrix_send_room_text_message( $bob, $room_id, body => "message" )
               ->SyTest::pass_on_done( "Message 2 Sent" ),
         )->SyTest::pass_on_done( "Message 2 Pushed" );
      })->then( sub {
         do_request_json_for( $alice,
              method  => "GET",
              uri     => "/r0/pushers",
         )->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( pushers ) );
            @{ $body->{pushers} } == 1 or die "Expected one pusher";

            Future->done(1);
         });
      });
   };
