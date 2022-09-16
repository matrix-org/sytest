# Per the specification HTTP pushers must point to the following location.
my $PUSH_LOCATION = "/_matrix/push/v1/notify";

sub create_pusher
{
   my ( $user, $app_id, $push_key, $url ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/v3/pushers/set",
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
   my ( $pushkey, $response ) = @_;

   await_http_request( $PUSH_LOCATION, sub {
      my ( $request ) = @_;
      my $body = $request->body_from_json;

      return unless $body->{notification}{type};
      return unless $body->{notification}{type} eq "m.room.message";

      # Ensure this is the expected pusher.
      return unless $body->{notification}{devices};
      return unless $body->{notification}{devices}[0]{pushkey} eq $pushkey;

      # Respond to expected request.
      $request->respond_json( $response // {} );

      return 1;
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

      my $url = $test_server_info->client_location . $PUSH_LOCATION;

      matrix_create_room_synced( $alice, visibility => "private" )->then( sub {
         ( $room_id ) = @_;

         matrix_invite_user_to_room_synced( $alice, $bob, $room_id );
      })->then( sub {
         matrix_join_room_synced( $bob, $room_id );
      })->then( sub {
         matrix_send_room_text_message_synced(
            $bob, $room_id, body => "message"
         );
      })->then( sub {
         my ( $event_id ) = @_;

         # Set a read receipt so that we pushed for the subsequent messages.
         matrix_advance_room_receipt_synced( $alice, $room_id,
            "m.read" => $event_id
         );
      })->then( sub {
         create_pusher( $alice, "sytest", "key_1", "$url" )
            ->SyTest::pass_on_done( "Alice's pusher 1 created" );
      })->then( sub {
         create_pusher( $alice, "sytest", "key_2", "$url" )
            ->SyTest::pass_on_done( "Alice's pusher 2 created" );
      })->then( sub {
         retry_until_success {
            do_request_json_for( $alice,
               method  => "GET",
               uri     => "/v3/pushers",
            )->then( sub {
               my ( $body ) = @_;

               assert_json_keys( $body, qw( pushers ) );
               @{ $body->{pushers} } == 2 or die "Expected two pushers";

               Future->done(1);
            });
         }
      })->then( sub {
         # It can take a while before we start receiving push on new pushers.
         retry_until_success {
            Future->needs_all(
               wait_for_push( "key_1" ),
               wait_for_push( "key_2" ),
               matrix_send_room_text_message_synced( $bob, $room_id, body => "message" )
            )
         }->SyTest::pass_on_done( "Message 1 Pushed" );
      })->then( sub {
         # Now we go and reject a push
         Future->needs_all(
            wait_for_push( "key_1", { rejected => [ "key_1" ] } ),
            wait_for_push( "key_2" ),
            matrix_send_room_text_message_synced( $bob, $room_id, body => "message" )
         )->SyTest::pass_on_done( "Message 2 Pushed" );
      })->then( sub {
         retry_until_success {
            do_request_json_for( $alice,
               method  => "GET",
               uri     => "/v3/pushers",
            )->then( sub {
               my ( $body ) = @_;

               assert_json_keys( $body, qw( pushers ) );
               @{ $body->{pushers} } == 1 or die "Expected one pusher";

               assert_eq( $body->{pushers}[0]{pushkey}, "key_2" );

               Future->done(1);
            });
         }
      });
   };
