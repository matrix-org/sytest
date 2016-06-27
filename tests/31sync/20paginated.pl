use Future::Utils qw( repeat try_repeat );

test "Can ask for paginated sync",
   requires => [ local_user_fixture( with_events => 0 ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_sync_post( $user,
         content => {
            pagination_config => {
               limit => 10,
               order => "m.origin_server_ts",
            }
         }
      );
   };

test "Requesting unknown room results in error",
   requires => [ local_user_fixture( with_events => 0 ) ],

   check => sub {
      my ( $user ) = @_;

      my $room_id = "!test:example.com";

      matrix_sync_post( $user,
         content => { extras => { peek => { $room_id => {} } } }
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body->{rooms}, qw( errors ) );
         assert_json_keys( $body->{rooms}{errors}, $room_id );
         assert_json_keys( $body->{rooms}{errors}{$room_id}, qw( error errcode ) );
         assert_eq( $body->{rooms}{errors}{$room_id}{errcode}, "M_CANNOT_PEEK" );

         Future->done(1);
      });
   };

multi_test "Basic paginated sync",
   requires => [ local_user_fixture( with_events => 0 ) ],

   timeout => 100,

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      my $num_rooms = 5;
      my $pagination_limit = 3;

      try_repeat( sub {
         matrix_create_room_synced( $user )
         ->then( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "First message",
            )
         });
      }, foreach => [ 1 .. $num_rooms ])
      ->then( sub {
         matrix_sync_post( $user,
            content => {
               pagination_config => {
                  limit => $pagination_limit,
                  order => "m.origin_server_ts",
               }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );

         $body->{pagination_info}{limited} or die "Limited flag is not set";

         # Check that the newest rooms are in the sync
         assert_json_keys( $body->{rooms}{join}, @rooms[$num_rooms - $pagination_limit .. $num_rooms - 1] );
         assert_eq( scalar keys $body->{rooms}{join}, $pagination_limit, "correct number of rooms");

         pass "Correct initial sync response";

         matrix_send_room_text_message_synced( $user, $rooms[0],
            body => "Second message",
         )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body of incremental sync", $body;

         assert_json_keys( $body, qw( pagination_info ) );

         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, 1, "correct number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         pass "Unseen room is in incremental sync";

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::true );

         first {
            $_->{content}{body} eq "Second message"
         } @{$room->{timeline}{events}} or die "Expected new message";

         assert_eq( $room->{timeline}{limited}, JSON::true, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 2, "two messages in timeline");

         pass "Got some historic data in newly seen room";

         first {
            $_->{type} eq "m.room.create"
         } @{$room->{state}{events}} or die "Expected creation event";

         pass "Got full state";

         matrix_send_room_text_message_synced( $user, $rooms[0],
            body => "Third message",
         )
      })->then(sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, 1, "correct number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::true );

         assert_eq( $room->{timeline}{limited}, JSON::false, "room is not limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 1, "one new messages in timeline");
         assert_eq( scalar @{$room->{state}{events}}, 0, "no new state");

         pass "Previously seen rooms do not have state.";

         my @roomssss_why_leo_why = @rooms;

         try_repeat( sub {
            my ( $room_id ) = @_;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "New message",
            )
         }, foreach => \@roomssss_why_leo_why )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         $body->{pagination_info}{limited} or die "Limited flag is not set";

         # Check that the newest rooms are in the sync
         assert_json_keys( $body->{rooms}{join}, @rooms[$num_rooms - $pagination_limit .. $num_rooms - 1] );
         assert_eq( scalar keys $body->{rooms}{join}, $pagination_limit, "correct number of rooms");

         pass "Incremental sync correctly limited.";

         matrix_send_room_text_message_synced( $user, $rooms[0],
            body => "Fourth message",
         )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );

         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, 1, "correct number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::true );

         first {
            $_->{content}{body} eq "Fourth message"
         } @{$room->{timeline}{events}} or die "Expected new message";

         assert_eq( $room->{timeline}{limited}, JSON::true, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 2, "two messages in timeline");

         first {
            $_->{type} eq "m.room.create"
         } @{$room->{state}{events}} or die "Expected creation event";

         pass "Got full state for room that had been seen but was then limited";

         Future->done( 1 );
      });
   };


multi_test "Can request unsen room",
   requires => [ local_user_fixture( with_events => 0 ) ],

   timeout => 100,

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      my $num_rooms = 5;
      my $pagination_limit = 3;

      try_repeat( sub {
         matrix_create_room_synced( $user )
         ->then( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "First message",
            )
         });
      }, foreach => [ 1 .. $num_rooms ])
      ->then( sub {
         matrix_sync_post( $user,
            content => {
               pagination_config => {
                  limit => $pagination_limit,
                  order => "m.origin_server_ts",
               }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );

         $body->{pagination_info}{limited} or die "Limited flag is not set";

         # Check that the newest rooms are in the sync
         assert_json_keys( $body->{rooms}{join}, @rooms[$num_rooms - $pagination_limit .. $num_rooms - 1] );
         assert_eq( scalar keys $body->{rooms}{join}, $pagination_limit, "correct number of rooms");

         pass "Correct initial sync response";

         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
               extras => { peek => { $rooms[0] => {} } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );

         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, 1, "correct number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         pass "Unseen room is in incremental sync";

         my $room = $body->{rooms}{join}{$rooms[0]};

         first {
            $_->{type} eq "m.room.message" && $_->{content}{body} eq "First message"
         } @{$room->{timeline}{events}} or die "Expected new message";

         assert_eq( $room->{timeline}{limited}, JSON::true, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 2, "two messages in timeline");

         pass "Got some historic data in newly seen room";

         first {
            $_->{type} eq "m.room.create"
         } @{$room->{state}{events}} or die "Expected creation event";

         pass "Got full state";

         matrix_send_room_text_message_synced( $user, $rooms[-1],
            body => "Another message",
         )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
               extras => { peek => { $rooms[0] => { since => $user->sync_next_batch } } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_eq( scalar keys $body->{rooms}{join}, 1, "number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[-1] );

         pass "Didn't get room again when peeking";

         matrix_send_room_text_message_synced( $user, $rooms[0],
            body => "Yet another message",
         )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_eq( scalar keys $body->{rooms}{join}, 1, "number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         first {
            $_->{type} eq "m.room.create"
         } @{$room->{state}{events}} or die "Expected creation event";

         assert_eq( $room->{timeline}{limited}, JSON::true, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 2, "two messages in timeline");

         pass "Room that was being peeked in gets fully synced";

         Future->done( 1 );
      });
   };

multi_test "Synced flag is correctly set when peeking",
   requires => [ local_user_fixture( with_events => 0 ) ],

   timeout => 100,

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      my $num_rooms = 5;
      my $pagination_limit = 3;

      try_repeat( sub {
         matrix_create_room_synced( $user )
         ->then( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "First message",
            )
         });
      }, foreach => [ 1 .. $num_rooms ])
      ->then( sub {
         matrix_sync_post( $user,
            content => {
               pagination_config => {
                  limit => $pagination_limit,
                  order => "m.origin_server_ts",
               }
            }
         );
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
               extras => { peek => { $rooms[0] => {} } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         pass "Unseen room is in incremental sync";

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::false );

         pass "Synced flag in peeked room is false";

         matrix_send_room_text_message_synced( $user, $rooms[-1],
            body => "Another message",
         )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
               extras => { peek => { $rooms[0] => { since => $user->sync_next_batch } } },
            }
         );
      })->then( sub {
         matrix_send_room_text_message_synced( $user, $rooms[0],
            body => "Yet another message",
         )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
               extras => { peek => { $rooms[0] => { since => $user->sync_next_batch } } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_eq( scalar keys $body->{rooms}{join}, 1, "number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::true );

         assert_eq( $room->{timeline}{limited}, JSON::false, "room isn't limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 1, "one message in timeline");

         pass "Synced flag set on room when received message while peeking";

         Future->done( 1 );
      });
   };

test "Can paginate paginated sync",
   requires => [ local_user_fixture( with_events => 0 ) ],

   timeout => 100,

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      my $num_rooms = 5;
      my $pagination_limit = 3;

      try_repeat( sub {
         matrix_create_room_synced( $user )
         ->then( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "First message",
            )
         });
      }, foreach => [ 1 .. $num_rooms ])
      ->then( sub {
         matrix_sync_post( $user,
            content => {
               pagination_config => {
                  limit => $pagination_limit,
                  order => "m.origin_server_ts",
               }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         $body->{pagination_info}{limited} or die "Limited flag is not set";

         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
               extras => { paginate => { limit => 10 } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, $num_rooms - $pagination_limit, "number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0 .. $num_rooms - $pagination_limit - 1] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::true );
         assert_eq( $room->{timeline}{limited}, JSON::true, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 2, "two messages in timeline");

         first {
            $_->{type} eq "m.room.create"
         } @{$room->{state}{events}} or die "Expected creation event";

         Future->done( 1 );
      });
   };

multi_test "Paginated sync inlcude tags",
   requires => [ local_user_fixture( with_events => 0 ) ],

   timeout => 100,

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      my $num_rooms = 5;
      my $pagination_limit = 3;

      try_repeat( sub {
         matrix_create_room_synced( $user )
         ->then( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "First message",
            )
         });
      }, foreach => [ 1 .. $num_rooms ])
      ->then( sub {
         matrix_add_tag_synced( $user, $rooms[0], "test_tag", {} );
      })->then( sub {
         matrix_sync_post( $user,
            content => {
               pagination_config => {
                  limit => $pagination_limit,
                  order => "m.origin_server_ts",
                  tags => "m.include_all",
               }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         $body->{pagination_info}{limited} or die "Limited flag is not set";

         # Check that the newest rooms are in the sync
         assert_json_keys( $body->{rooms}{join}, @rooms[$num_rooms - $pagination_limit .. $num_rooms - 1, 0] );
         assert_eq( scalar keys $body->{rooms}{join}, $pagination_limit + 1, "correct number of rooms");

         pass "Tagged room is in initial sync";

         matrix_send_room_text_message_synced( $user, $rooms[0],
            body => "Second message",
         )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, 1, "number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::true );
         assert_eq( $room->{timeline}{limited}, JSON::false, "room is not limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 1, "one message in timeline");
         assert_eq( scalar @{$room->{state}{events}}, 0, "no state");

         pass "Tagged room does not have full state in incremental sync";

         Future->done( 1 );
      });
   };


test "Paginated sync ignore tags",
   requires => [ local_user_fixture( with_events => 0 ) ],

   timeout => 100,

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      my $num_rooms = 5;
      my $pagination_limit = 3;

      try_repeat( sub {
         matrix_create_room_synced( $user )
         ->then( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "First message",
            )
         });
      }, foreach => [ 1 .. $num_rooms ])
      ->then( sub {
         matrix_add_tag_synced( $user, $rooms[0], "test_tag", {} );
      })->then( sub {
         matrix_sync_post( $user,
            content => {
               pagination_config => {
                  limit => $pagination_limit,
                  order => "m.origin_server_ts",
                  tags => "m.ignore",
               }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         $body->{pagination_info}{limited} or die "Limited flag is not set";

         # Check that the newest rooms are in the sync
         assert_json_keys( $body->{rooms}{join}, @rooms[$num_rooms - $pagination_limit .. $num_rooms - 1] );
         assert_eq( scalar keys $body->{rooms}{join}, $pagination_limit, "correct number of rooms");

         Future->done( 1 );
      });
   };

multi_test "Paginated sync with tags handles tag changes correctly",
   requires => [ local_user_fixture( with_events => 0 ) ],

   timeout => 100,

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      my $num_rooms = 5;
      my $pagination_limit = 3;

      try_repeat( sub {
         matrix_create_room_synced( $user )
         ->then( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "First message",
            )
         });
      }, foreach => [ 1 .. $num_rooms ])
      ->then( sub {
         matrix_sync_post( $user,
            content => {
               pagination_config => {
                  limit => $pagination_limit,
                  order => "m.origin_server_ts",
                  tags => "m.include_all",
               }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         $body->{pagination_info}{limited} or die "Limited flag is not set";

         # Check that the newest rooms are in the sync
         assert_json_keys( $body->{rooms}{join}, @rooms[$num_rooms - $pagination_limit .. $num_rooms - 1] );
         assert_eq( scalar keys $body->{rooms}{join}, $pagination_limit, "correct number of rooms");

         matrix_add_tag_synced( $user, $rooms[0], "test_tag", {} );
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, 1, "number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::true );
         assert_eq( $room->{timeline}{limited}, JSON::true, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 2, "two messages in timeline");

         first {
            $_->{type} eq "m.room.create"
         } @{$room->{state}{events}} or die "Expected creation event";

         pass "Newly tagged room has full state in incremental sync";

         matrix_remove_tag_synced( $user, $rooms[0], "test_tag" );
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, 1, "number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::false );
         assert_eq( $room->{timeline}{limited}, JSON::false, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 0, "no messages in timeline");
         assert_eq( scalar @{$room->{state}{events}}, 0, "no state");

         pass "Untagged room gets unsynced";

         matrix_add_tag_synced( $user, $rooms[0], "test_tag", {} );
      })->then( sub {
         matrix_remove_tag_synced( $user, $rooms[0], "test_tag" );
      })->then( sub {
         matrix_add_tag_synced( $user, $rooms[0], "test_tag", {} );
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, 1, "number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::true );
         assert_eq( $room->{timeline}{limited}, JSON::true, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 2, "two messages in timeline");

         first {
            $_->{type} eq "m.room.create"
         } @{$room->{state}{events}} or die "Expected creation event";

         pass "Newly retagged room has full state in incremental sync";

         Future->done( 1 );
      });
   };

test "Removed room tag includes message",
   requires => [ local_user_fixture( with_events => 0 ) ],

   timeout => 100,

   check => sub {
      my ( $user ) = @_;
      my @rooms;

      my $num_rooms = 5;
      my $pagination_limit = 3;

      try_repeat( sub {
         matrix_create_room_synced( $user )
         ->then( sub {
            my ( $room_id ) = @_;

            push @rooms, $room_id;

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "First message",
            )
         });
      }, foreach => [ 1 .. $num_rooms ])
      ->then( sub {
         matrix_sync_post( $user,
            content => {
               pagination_config => {
                  limit => $pagination_limit,
                  order => "m.origin_server_ts",
                  tags => "m.include_all",
               }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         $body->{pagination_info}{limited} or die "Limited flag is not set";

         # Check that the newest rooms are in the sync
         assert_json_keys( $body->{rooms}{join}, @rooms[$num_rooms - $pagination_limit .. $num_rooms - 1] );
         assert_eq( scalar keys $body->{rooms}{join}, $pagination_limit, "correct number of rooms");

         matrix_add_tag_synced( $user, $rooms[0], "test_tag", {} );
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
            }
         );
      })->then( sub {
         matrix_remove_tag_synced( $user, $rooms[0], "test_tag" );
      })->then( sub {
         matrix_send_room_text_message_synced( $user, $rooms[0],
            body => "Second message",
         )
      })->then( sub {
         matrix_sync_post_again( $user,
            content => {
               filter => { room => { timeline => { limit => 2 } } },
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( pagination_info ) );
         not $body->{pagination_info}{limited} or die "Limited flag is set";

         assert_eq( scalar keys $body->{rooms}{join}, 1, "number of rooms");
         assert_json_keys( $body->{rooms}{join}, $rooms[0] );

         my $room = $body->{rooms}{join}{$rooms[0]};

         assert_eq( $room->{synced}, JSON::false );
         assert_eq( $room->{timeline}{limited}, JSON::false, "room is limited");
         assert_eq( scalar @{$room->{timeline}{events}}, 1, "one message in timeline");
         assert_eq( scalar @{$room->{state}{events}}, 0, "no state");

         Future->done( 1 );
      });
   };
