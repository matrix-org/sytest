use Future::Utils qw( repeat );

test "Lazy loading parameters in the filter are strictly boolean",
   requires => [ local_user_fixtures( 1 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice ) = @_;

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => "true",
            },
         }
      })->main::expect_http_400()
      ->then( sub {
         matrix_create_filter( $alice, {
            room => {
               state => {
                  lazy_load_members => 1,
               },
            }
         })->main::expect_http_400()
      })->then( sub {
         matrix_create_filter( $alice, {
            room => {
               state => {
                  include_redundant_members => "true",
               },
            }
         })->main::expect_http_400()
      })->then( sub {
         matrix_create_filter( $alice, {
            room => {
               state => {
                  include_redundant_members => 1,
               },
            }
         })->main::expect_http_400()
      })->then( sub {
         Future->done(1);
      });
   };

test "The only membership state included in an initial sync is for all the senders in the timeline",
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
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
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


test "The only membership state included in an incremental sync is for senders in the timeline",
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
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message_synced( $bob, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $bob->user_id ]);

         matrix_send_room_text_message_synced( $charlie, $room_id,
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


test "The only membership state included in a gapped incremental sync is for senders in the timeline",
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
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
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


test "Old members are included in gappy incr LL sync if they start speaking",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Alice initial syncs with a filter on the last 10 events, and LL members
      # Alice should see only Bob in the membership list.
      # Charlie then sends 10 events
      # Alice syncs again; she should get a gappy sync and see
      # Charlie's membership (due to his timeline events).

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
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $bob, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 20 ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $bob->user_id
         ]);

         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $charlie, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 20 ])
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $charlie->user_id,
         ]);
         Future->done(1);
      });
   };


test "Members from the gap are included in gappy incr LL sync",
   requires => [ local_user_fixtures( 4 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie, $dave ) = @_;

      # Alice creates a public room,
      # Bob and Charlie join.
      # Bob sends 10 events into it
      # Alice initial syncs with a filter on the last 10 events, and LL members
      # Alice should see only Bob in the membership list.
      # Dave joins
      # Charlie then sends 10 events
      # Alice syncs again; she should get a gappy sync and see both
      # Charlie's membership (due to his timeline events) and
      # Dave's membership (because he joined during the gap)

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
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
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
         assert_room_members( $body, $room_id, [
            $bob->user_id
         ]);

         matrix_join_room( $dave, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $charlie, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         matrix_sync_again( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [
            $charlie->user_id,
            $dave->user_id
         ]);
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
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
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

            matrix_send_room_text_message_synced( $charlie, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 5 ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         assert_room_members( $body, $room_id, [ $bob->user_id, $charlie->user_id ]);

         matrix_send_room_text_message_synced( $bob, $room_id,
            body => "New message from bob",
         )
      })->then( sub {
         matrix_send_room_text_message_synced( $charlie, $room_id,
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
         matrix_put_room_state( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
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

            matrix_send_room_text_message_synced( $charlie, $room_id,
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
         matrix_send_room_text_message_synced( $charlie, $room_id,
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
