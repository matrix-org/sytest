test "Messages that notify from another user increment unread notification count",
   requires => [ local_user_fixture( with_events => 0 ),
		 local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

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
         matrix_sync( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         assert_json_keys( $room, "unread_notifications" );
         my $unread = $room->{unread_notifications};
         assert_json_keys( $unread, "notification_count" );

         $unread->{notification_count} == 0
            or die "Expected unread notification count to be 0";

         matrix_send_room_text_message( $user2, $room_id,
            body => "Test message 2",
         );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         assert_json_keys( $room, "unread_notifications" );
         my $unread = $room->{unread_notifications};
         assert_json_keys( $unread, "notification_count" );

         $unread->{notification_count} == 1
            or die "Expected unread notification count to be 1";

         Future->done(1);
      })
   };

test "Messages that highlight from another user increment unread highlight count",
   requires => [ local_user_fixture( with_events => 0 ),
		 local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my $room_id;

      matrix_add_push_rule( $user1, 'global', 'content', 'anything', {
         pattern => "*",
         actions => [ "notify", { set_tweak => "highlight", value => JSON::true } ]
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

         matrix_advance_room_receipt_synced( $user1, $room_id, "m.read" => $event_id );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         assert_json_keys( $room, "unread_notifications" );
         my $unread = $room->{unread_notifications};
         assert_json_keys( $unread, "highlight_count" );

         $unread->{highlight_count} == 0
            or die "Expected unread highlight count to be 0";

         matrix_send_room_text_message_synced( $user2, $room_id,
            body => "Test message 2",
         );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         assert_json_keys( $room, "unread_notifications" );
         my $unread = $room->{unread_notifications};
         assert_json_keys( $unread, "highlight_count" );

         $unread->{highlight_count} == 1
            or die "Expected unread highlight count to be 1";

         Future->done(1);
      })
   };
