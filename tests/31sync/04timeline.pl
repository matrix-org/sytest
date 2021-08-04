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
         matrix_send_room_text_message_synced( $user, $room_id,
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

         matrix_send_room_text_message_synced( $user, $room_id,
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

      my ( $filter_id, $room_id, $event_id );

      my $filter = {
         room => {
            timeline => { limit => 1 },
            state    => { types => [] },
         },
         presence => { types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         matrix_send_room_text_message_synced( $user, $room_id,
            body => "A test message", txn_id => "my_transaction_id"
         );
      })->then( sub {
         ( $event_id ) = @_;

         log_if_fail "Sent test message, id $event_id";

         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Sync response", $body;

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
         account_data => { types => [] },
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

         matrix_send_filler_messages_synced( $user, $room_id, 12 );
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

         matrix_create_room_synced( $user );
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

      my ( $filter_id, $room_id );

      my $filter = { room => { timeline => { limit => 1 } } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         Future->needs_all( map {
            matrix_send_room_message( $user, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 10 );
      })->then( sub {
         matrix_send_room_message_synced( $user, $room_id,
            content => { "filler" => 11 },
            type    => "another.filler.type",
         );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id, full_state => 'true' );
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

         matrix_send_room_text_message_synced( $user, $room_id,
            body => "2"
         );
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


test "A prev_batch token from incremental sync can be used in the v1 messages API",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $room_id, $event_id_1, $event_id_2 );

      matrix_create_room( $user )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message_synced( $user, $room_id, body => "1" );
      })->then( sub {
         ( $event_id_1 ) = @_;
         matrix_sync( $user )
      })->then( sub {
         matrix_send_room_text_message_synced( $user, $room_id,
            body => "2"
         );
      })->then( sub {
         ( $event_id_2 ) = @_;

         matrix_sync_again( $user );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

	 log_if_fail "Sync for room", $room;

         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{state}, qw( events ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));
         @{ $room->{timeline}{events} } == 1
            or die "Expected only one timeline event";
         $room->{timeline}{events}[0]{event_id} eq $event_id_2
            or die "Unexpected timeline event";

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



test "A next_batch token can be used in the v1 messages API",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $next_batch, $event_id_1, $event_id_2 );

      my $filter = { room => { timeline => { limit => 1 } } };

      # we send an event, then sync, then send another event,
      # and check that we can paginate forward from the sync.

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message_synced( $user, $room_id,
            body => "1"
         );
      })->then( sub {
         ( $event_id_1 ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_eq( $room->{timeline}{events}[0]{event_id}, $event_id_1,
                    "Event ID 1" );

         $next_batch = $body->{next_batch};

         matrix_send_room_text_message( $user, $room_id, body => "2" );
      })->then( sub {
         ( $event_id_2 ) = @_;

         matrix_get_room_messages( $user, $room_id,
                                   from => $next_batch,
                                   dir => 'f' );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk start end ) );
         assert_eq( scalar @{ $body->{chunk} }, 1, "event count" );
         assert_eq( $body->{chunk}[0]{event_id}, $event_id_2,
                    "Event ID 2" );
         assert_eq( $body->{chunk}[0]{content}{body}, "2",
                    "Message body" );

         Future->done(1);
      })
   };
