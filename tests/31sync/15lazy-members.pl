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


sub assert_room_members {
   my ( $body, $room_id, $member_ids ) = @_;

   my $room = $body->{rooms}{join}{$room_id};
   my $timeline = $room->{timeline}{events};

   log_if_fail "Room", $room;

   assert_json_keys( $room, qw( timeline state ephemeral ));

   my @members = grep { $_->{type} eq 'm.room.member' } @{ $room->{state}{events} };
   @members == scalar @{ $member_ids }
      or die "Expected only ".(scalar @{ $member_ids })." membership events";

   my $found_senders = {};
   my $found_state_keys = {};

   foreach my $event (@members) {
      $event->{type} eq "m.room.member"
         or die "Unexpected state event type";

      assert_json_keys( $event, qw( sender state_key content ));

      $found_senders->{ $event->{sender} }++;
      $found_state_keys->{ $event->{state_key} }++;

      assert_json_keys( my $content = $event->{content}, qw( membership ));

      $content->{membership} eq "join" or
         die "Expected membership as 'join'";
   }

   foreach my $user_id (@{ $member_ids }) {
      assert_eq( $found_senders->{ $user_id }, 1,
                 "Expected membership event sender for ".$user_id );
      assert_eq( $found_state_keys->{ $user_id }, 1,
                 "Expected membership event state key for ".$user_id );
   }
}
