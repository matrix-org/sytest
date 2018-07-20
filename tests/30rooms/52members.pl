use List::Util qw( first );

test "Can get rooms/{roomId}/members",
   requires => [ local_user_fixture(), local_user_fixture(), qw ( can_send_message ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      matrix_create_and_join_room( [ $user1, $user2 ] )->then( sub {
         my ( $room_id ) = @_;

         do_request_json_for( $user1,
            method => "GET",
            uri => "/r0/rooms/$room_id/members",
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         assert_room_members_in_state( $body->{chunk}, [
            $user1->user_id,
            $user2->user_id,
         ]);

         Future->done(1);
      })
   };


test "Can get rooms/{roomId}/members at a given point",
   requires => [
      local_user_fixture(), local_user_fixture(),
      qw ( can_send_message )
   ],

   check => sub {
      my ( $user1, $user2 ) = @_;
      my ( $room_id, $event_id );

      matrix_create_and_join_room( [ $user1 ] )->then( sub {
         ( $room_id ) = @_;
         matrix_send_room_text_message( $user1, $room_id,
            body => "Hello world",
         );
      })->then( sub {
         ( $event_id ) = @_;
         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $user1, $room_id,
            body => "Hello back",
         );
      })->then( sub {
         do_request_json_for( $user1,
            method => "GET",
            uri => "/r0/rooms/$room_id/members",
            params => {
               at => $event_id
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         # as of the first 'Hello world' the only member in the room should be user1
         assert_room_members_in_state( $body->{chunk}, [ $user1->user_id ]);

         Future->done(1);
      })
   };

