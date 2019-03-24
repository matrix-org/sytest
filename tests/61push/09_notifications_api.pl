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

         # We need to send a read receipt before the server will start
         # calculating notifications.
         matrix_advance_room_receipt( $user1, $room_id, "m.read" => $event_id );
      })->then( sub {
         # It may take a while for the server to start calculating
         # notifications, so we repeatedly send message and check if anything
         # turns up in `/notifications`
         retry_until_success {
            matrix_send_room_text_message( $user2, $room_id,
               body => "Test message 2",
            )->then(sub {
               do_request_json_for( $user1,
                  method  => "GET",
                  uri     => "/unstable/notifications",
               )->then( sub {
                  my ( $body ) = @_;

                  log_if_fail( "first /notifications response", $body );

                  assert_json_keys( $body, "notifications" );

                  my $notifs = $body->{notifications};

                  # We just want something to turn up
                  scalar @{ $notifs } or die "no notifications";

                  Future->done( $notifs->[0] );
               });
            });
         }
      })->then( sub {
         my ( $notif ) = @_;

         # Check the notif has the expected keys
         assert_json_keys( $notif, qw( room_id actions event read ts ) );
         assert_ok( exists $notif->{profile_tag}, "profile_tag defined" );
         assert_eq( $notif->{read}, JSON::false );

         # Now we send a message and advance the read receipt up until that
         # point, and test that notifications becomes empty
         matrix_send_room_text_message( $user2, $room_id,
            body => "Test message 3",
         );
      })->then( sub {
         my ( $event_id ) = @_;

         matrix_advance_room_receipt( $user1, $room_id, "m.read" => $event_id );
      })->then( sub {
         retry_until_success {
            do_request_json_for( $user1,
               method  => "GET",
               uri     => "/unstable/notifications",
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail( "second /notifications response", $body );

               assert_json_keys( $body, "notifications" );

               assert_eq( scalar @{ $body->{notifications} }, 0 );

               Future->done(1);
            });
         }
      });
   };

