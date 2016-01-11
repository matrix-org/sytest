test "Can sync a room with a single message",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id_1, $event_id_2 );

      my $filter = { room => { timeline => { limit => 2 } } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id,
            body => "Test message 1",
         );
      })->then( sub {
         ( $event_id_1 ) = @_;

         matrix_send_room_text_message( $user, $room_id,
            body => "Test message 2",
         );
      })->then( sub {
         ( $event_id_2 ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         @{ $room->{timeline}{events} } == 2
            or die "Expected two timeline events";
         $room->{timeline}{events}[0]{event_id} eq $event_id_1
            or die "Unexpected timeline event";
         $room->{timeline}{events}[0]{content}{body} eq "Test message 1"
            or die "Unexpected message body.";
         $room->{timeline}{events}[1]{event_id} eq $event_id_2
            or die "Unexpected timeline event";
         $room->{timeline}{events}[1]{content}{body} eq "Test message 2"
            or die "Unexpected message body.";
         $room->{timeline}{limited}
            or die "Expected timeline to be limited";

         Future->done(1);
      })
   };


test "Can sync a room with a message with a transaction id",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id );

      my $filter = {
         room => {
            timeline => { limit => 1 },
            state => { types => [] },
         },
         presence => { types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id,
            body => "A test message", txn_id => "my_transaction_id"
         );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         @{ $room->{timeline}{events} } == 1
            or die "Expected only one timeline event";
         $room->{timeline}{events}[0]{event_id} eq $event_id
            or die "Unexpected timeline event";
         $room->{timeline}{events}[0]{content}{body} eq "A test message"
            or die "Unexpected message body.";
         $room->{timeline}{events}[0]{unsigned}{transaction_id} eq "my_transaction_id"
            or die "Unexpected transaction id";
         $room->{timeline}{limited}
            or die "Expected timeline to be limited";

         Future->done(1);
      })
   };


test "A message sent after an initial sync appears in the timeline of an incremental sync.",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id, $next_batch );

      my $filter = {
         room => {
            timeline => { limit => 1 },
            state    => { types => [] },
         },
         presence => { types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};
         matrix_send_room_text_message( $user, $room_id,
            body => "A test message", txn_id => "my_transaction_id"
         );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_sync( $user, filter => $filter_id, since => $next_batch );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{state}, qw( events ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         assert_json_empty_list( $room->{state}{events} );
         @{ $room->{timeline}{events} } == 1
            or die "Expected only one timeline event";
         $room->{timeline}{events}[0]{event_id} eq $event_id
            or die "Unexpected timeline event";
         $room->{timeline}{events}[0]{content}{body} eq "A test message"
            or die "Unexpected message body.";
         $room->{timeline}{events}[0]{unsigned}{transaction_id} eq "my_transaction_id"
            or die "Unexpected transaction id";
         (not $room->{timeline}{limited})
            or die "Did not expect timeline to be limited";

         Future->done(1);
      })
   };


test "A filtered timeline reaches its limit",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id );

      my $filter = {
         room => {
            timeline => { limit => 1, types => ["m.room.message"] },
            state    => { types => [] },
         },
         presence => { types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id,
            body => "My message"
         );
      })->then( sub {
         ( $event_id ) = @_;

         Future->needs_all( map {
            matrix_send_room_message( $user, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 10 );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{state}, qw( events ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         assert_json_empty_list( $room->{state}{events} );
         @{ $room->{timeline}{events} } == 1
            or die "Expected only one timeline event";
         $room->{timeline}{events}[0]{event_id} eq $event_id
            or die "Unexpected timeline event";
         $room->{timeline}{events}[0]{content}{body} eq "My message"
            or die "Unexpected message body.";
         (not $room->{timeline}{limited})
            or die "Did not expect timeline to be limited";

         Future->done(1)
      });
   };


test "Syncing a new room with a large timeline limit isn't limited",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id );

      my $filter = { room => { timeline => { limit => 100 } } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{state}, qw( events ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         (not $room->{timeline}{limited})
            or die "Did not expect timeline to be limited";

         Future->done(1);
      })
   };


test "A full_state incremental update returns only recent timeline",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $next_batch );

      my $filter = { room => { timeline => { limit => 1 } } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};
         Future->needs_all( map {
            matrix_send_room_message( $user, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 10 );
      })->then( sub {
         matrix_send_room_message( $user, $room_id,
               content => { "filler" => $_ },
               type    => "another.filler.type",
             );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next_batch,
             full_state => 'true');
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));

         @{ $room->{timeline}{events} } == 1
             or die "Expected only one timeline event";
         my $event = $room->{timeline}{events}[0];
         $event->{type} eq "another.filler.type"
            or die "Unexpected timeline event type";

         Future->done(1);
      })
   };


test "A prev_batch token can be used in the v1 messages API",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id_1, $event_id_2 );

      my $filter = { room => { timeline => { limit => 1 } } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "1" );
      })->then( sub {
         ( $event_id_1 ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "2" );
      })->then( sub {
         ( $event_id_2 ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{state}, qw( events ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         @{ $room->{timeline}{events} } == 1
            or die "Expected only one timeline event";
         $room->{timeline}{events}[0]{event_id} eq $event_id_2
            or die "Unexpected timeline event";
         $room->{timeline}{events}[0]{content}{body} eq "2"
            or die "Unexpected message body.";
         $room->{timeline}{limited}
            or die "Expected timeline to be limited";

         matrix_get_room_messages( $user, $room_id,
            from  => $room->{timeline}{prev_batch},
            limit => 1,
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk start end ) );
         @{ $body->{chunk} } == 1 or die "Expected only one event";
         $body->{chunk}[0]{event_id} eq $event_id_1
            or die "Unexpected event";
         $body->{chunk}[0]{content}{body} eq "1"
            or die "Unexpected message body.";

         Future->done(1);
      })
   };
