use Future::Utils qw( repeat );

test "The only membership state included in an initial sync are for all the senders in the timeline",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Charlie sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # She should only see Charlie in the membership list.

      my ( $filter_id, $room_id, $event_id_1, $event_id_2 );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $bob, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $charlie, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members ( $body, $room_id, [ $charlie->user_id ]);
         Future->done(1);
      });
   };


test "The only membership state included in an incremental sync are for senders in the timeline",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # Alice should see only Bob in the membership list.
      # Charlie sends an event
      # Alice syncs again; she should only see Charlie's membership event
      # in the incremental sync as Charlie sent anything in this timeframe.

      my ( $filter_id, $room_id, $event_id_1, $event_id_2 );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $bob, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $bob->user_id ]);

         matrix_send_room_text_message( $charlie, $room_id,
            body => "Message from charlie",
         )
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $charlie->user_id ]);
         Future->done(1);
      });
   };


test "The only membership state included in a gapped incremental sync are for senders in the timeline",
   requires => [ local_user_fixtures( 4 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie, $dave ) = @_;

      # Alice creates a public room,
      # Bob and Charlie and Dave join.
      # Bob sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # Alice should see only Bob in the membership list.
      # Charlie then sends 10 events
      # Dave then sends 10 events
      # Alice syncs again; she should get a gappy sync and only see
      # Dave's membership event as Charlie's never hit her at all.

      my ( $filter_id, $room_id, $event_id_1, $event_id_2 );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_join_room( $dave, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $bob, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $bob->user_id ]);

         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $charlie, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $dave, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $dave->user_id ]);
         Future->done(1);
      });
   };


test "We don't send redundant membership state across incremental syncs by default",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join
      # Bob sends 10 events into it
      # Charlie sends 5 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # Alice should see only Bob and Charlie in the membership list.
      # Bob sends 1 more event
      # Charlie sends 1 more event
      # Alice syncs again; she should not see any membership events as
      # the redundant ones for Bob and Charlie are removed.

      # TODO: speed up time and check that if we wait an hour then the server's
      # cache will expire and we'll send redundant members over anyway in the next
      # sync.

      my ( $filter_id, $room_id, $event_id_1, $event_id_2 );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $bob, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $charlie, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 5 ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $bob->user_id, $charlie->user_id ]);

         matrix_send_room_text_message( $bob, $room_id,
            body => "New message from bob",
         )
      })->then( sub {
         matrix_send_room_text_message( $charlie, $room_id,
            body => "New message from charlie",
         )
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, []);
         Future->done(1);
      });
   };


test "We do send redundant membership state across incremental syncs if asked",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join
      # Bob sends 10 events into it
      # Charlie sends 5 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      #   and include_redundant_members
      # Alice should see only Bob and Charlie in the membership list.
      # Bob sends 1 more event
      # Charlie sends 1 more event
      # Alice syncs again; she should see redundant membership events for Bob and
      # Charlie again

      my ( $filter_id, $room_id, $event_id_1, $event_id_2 );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true,
               include_redundant_members => JSON::true,
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $bob, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $charlie, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 5 ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $bob->user_id, $charlie->user_id ]);

         matrix_send_room_text_message( $bob, $room_id,
            body => "New message from bob",
         )
      })->then( sub {
         matrix_send_room_text_message( $charlie, $room_id,
            body => "New message from charlie",
         )
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $bob->user_id, $charlie->user_id ]);
         Future->done(1);
      });
   };
