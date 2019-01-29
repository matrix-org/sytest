use URI::Escape::XS qw( uri_escape );

test "/context/ on joined room works",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_send_room_text_message( $user, $room_id,
         body => "hello, world",
      )->then( sub {
         my ( $event_id ) = @_;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/context/${ \uri_escape( $event_id ) }",
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( state event ) );

         Future->done( 1 )
      });
   };

test "/context/ on non world readable room does not work",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   check => sub {
      my ( $user, $room_id, $other_user ) = @_;

      matrix_send_room_text_message( $user, $room_id,
         body => "hello, world",
      )->then( sub {
         my ( $event_id ) = @_;

         do_request_json_for( $other_user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/context/${ \uri_escape( $event_id ) }",
         );
      })->main::expect_http_403;
   };

test "/context/ returns correct number of events",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      my ( $event_before_id, $event_middle_id, $event_after_id );

      matrix_send_room_text_message( $user, $room_id,
         body => "event before",
      )->then( sub {
         ( $event_before_id ) = @_;

         log_if_fail "Before event", $event_before_id;

         matrix_send_room_text_message( $user, $room_id,
            body => "hello, world",
         )
      })->then( sub {
         ( $event_middle_id ) = @_;

         log_if_fail "Middle event", $event_middle_id;

         matrix_send_room_text_message( $user, $room_id,
            body => "event after",
         )
      })->then( sub {
         ( $event_after_id ) = @_;

         log_if_fail "After event", $event_after_id;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/context/${ \uri_escape( $event_middle_id ) }",
            params    => {
               limit => 2,
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( state event events_before events_after start end ) );

         assert_json_list( my $before = $body->{events_before} );
         assert_eq( $before->[0]->{event_id}, $event_before_id, "event before" );

         assert_json_list( my $after = $body->{events_after} );
         assert_eq( $after->[0]->{event_id}, $event_after_id, "event after" );

         Future->done( 1 )
      });
   };

test "/context/ with lazy_load_members filter works",
   requires => [ local_user_and_room_fixtures(), local_user_fixtures( 2 ) ],

   check => sub {
      my ( $user, $room_id, $user2, $user3 ) = @_;

      matrix_join_room( $user2, $room_id )->then( sub {
         matrix_join_room( $user3, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id,
            body => "hello, world 1",
         );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id,
            body => "hello, world 2",
         );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id,
            body => "hello, world 3",
         );
      })->then( sub {
         my ( $event_id ) = @_;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/context/${ \uri_escape( $event_id ) }",
            params  => {
               limit => 2,
               filter  => '{ "lazy_load_members" : true }',
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( state event ) );

         # only the user who sent 'hello world' should be present in the state
         assert_state_room_members_match( $body->{state}, [ $user->user_id ]);

         Future->done( 1 )
      });
   };

