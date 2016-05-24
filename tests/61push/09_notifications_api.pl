test "Notifications can be viewed with GET /notifications",
   requires => [ local_user_fixture( with_events => 0 ),
		 local_user_fixture( with_events => 0 ),
               ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my $room_id;

      matrix_add_push_rule( $user1, 'global', 'content', 'anything', {
         pattern => "*",
         actions => [ "notify" ]
      })->then( sub {
         matrix_create_room( $user1 );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $user2, $room_id,
            body => "Test message 1",
         );
      })->then( sub {
         my ( $event_id ) = @_;

         matrix_advance_room_receipt( $user1, $room_id, "m.read" => $event_id );
      })->then( sub {
         matrix_send_room_text_message( $user2, $room_id,
            body => "Test message 2",
         );
      })->then( sub {
         do_request_json_for( $user1,
            method  => "GET",
            uri     => "/unstable/notifications",
         );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail("first /notifications response", $body);

         assert_json_keys( $body, "notifications" );

         my $notifs = $body->{notifications};

         assert_json_keys( $notifs->[0], qw(room_id actions event read ts) );
         # XXX: We can't assert that a key is present but null so can't test
         # profile_tag

         my $notif = $notifs->[0];
         assert_eq( $notif->{read}, JSON::false );

         matrix_advance_room_receipt( $user1, $room_id, "m.read" => $notif->{event}{event_id} );
      })->then( sub {
         do_request_json_for( $user1,
            method  => "GET",
            uri     => "/unstable/notifications",
         );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail("first /notifications response", $body);

         assert_json_keys( $body, "notifications" );

         my $notif = $body->{notifications}[0];
         assert_eq( $notif->{read}, JSON::true );

         Future->done(1);
      })
   };

