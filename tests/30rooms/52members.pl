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

         assert_state_room_members_match( $body->{chunk}, [
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
      my ( $room_id, $at_token );

      matrix_create_and_join_room( [ $user1 ] )->then( sub {
         ( $room_id ) = @_;
         matrix_send_room_text_message( $user1, $room_id,
            body => "Hello world",
         );
      })->then( sub {
         matrix_sync ( $user1 );
      })->then( sub {
         my ( $body ) = @_;
         # find the token at this point so we can query it later
         $at_token = $body->{rooms}->{join}->{$room_id}->{timeline}->{prev_batch};

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
               at => $at_token
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         # as of the first 'Hello world' the only member in the room should be user1
         assert_state_room_members_match( $body->{chunk}, [ $user1->user_id ]);

         Future->done(1);
      })
   };

test "Can filter rooms/{roomId}/members",
   requires => [
      local_user_fixture(), local_user_fixture(),
      qw ( can_send_message )
   ],

   check => sub {
      my ( $user1, $user2 ) = @_;
      my $room_id;

      matrix_create_and_join_room( [ $user1, $user2 ] )->then( sub {
         ( $room_id ) = @_;
         matrix_leave_room( $user2, $room_id );
      })->then( sub {
         do_request_json_for( $user1,
            method => "GET",
            uri => "/r0/rooms/$room_id/members",
            params => {
               not_membership => 'leave',
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );
         assert_state_room_members_match( $body->{chunk}, { $user1->user_id => 'join' } );

         do_request_json_for( $user1,
            method => "GET",
            uri => "/r0/rooms/$room_id/members",
            params => {
               membership => 'leave',
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );
         assert_state_room_members_match( $body->{chunk}, { $user2->user_id => 'leave' });

         do_request_json_for( $user1,
            method => "GET",
            uri => "/r0/rooms/$room_id/members",
            params => {
               membership => 'join',
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );
         assert_state_room_members_match( $body->{chunk}, { $user1->user_id => 'join' });
         Future->done(1);
      })
   };
