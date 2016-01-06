multi_test "Limit on room/initialSync is reached over federation (SYN-482)",
   requires => [ local_user_and_room_fixtures(), remote_user_fixture() ],

   bug => 'SYN-482',

   check => sub {
      my ( $user_a, $room_id, $user_b ) = @_;
      my $messages_events;
      my $sync_events;

      matrix_set_room_history_visibility( $user_a, $room_id, "invited" )
      ->then( sub {
         matrix_invite_user_to_room( $user_a, $user_b, $room_id )
      })->then( sub {
         Future->needs_all(map {
            matrix_send_room_text_message( $user_a, $room_id,
               body => "Message #$_",
            )
         } 1..3)
      })->then( sub {
         matrix_join_room( $user_b, $room_id )
      })->then( sub {
         matrix_initialsync_room( $user_b, $room_id, limit => 10 );
      })->then( sub {
         my ($body) = @_;
         $sync_events = $body->{messages}->{chunk};

         matrix_get_room_messages( $user_b, $room_id, limit => 10 );
      })->then( sub {
         my ($body) = @_;

         $messages_events = ${body}->{chunk};

         @$sync_events == @$messages_events or die "Received different number of messages in  rooms/{roomId}/initialSync compared to rooms/{roomId}/messages";

         Future->done(1);
      })
   };
