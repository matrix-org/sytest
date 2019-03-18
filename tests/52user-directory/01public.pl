test "User appears in user directory",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      my $searching_user;

      my $displayname = generate_random_displayname();
      my $searching_displayname = generate_random_displayname();

      matrix_set_displayname( $user, $displayname )
      ->then( sub {
         matrix_create_user_on_server( $user->http,
            displayname => $searching_displayname
         );
      })->then( sub {
         ( $searching_user ) = @_;

         matrix_create_room( $user,
            preset => "public_chat",
         );
      })->then( sub {
         my ( $room_id ) = @_;
         matrix_join_room( $searching_user, $room_id );
      })->then( sub {
         repeat_until_true {
            do_request_json_for( $searching_user,
               method  => "POST",
               uri     => "/r0/user_directory/search",
               content => {
                  search_term => $displayname,
               }
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "Body", $body;

               assert_json_keys( $body, qw( results ) );
               assert_json_list( my $results = $body->{results} );

               Future->done( any { $_->{user_id} eq $user->user_id } @$results );
            });
         };
      });
   };

test "User in private room doesn't appear in user directory",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      my $searching_user;

      my $displayname = generate_random_displayname();
      my $searching_displayname = generate_random_displayname();

      matrix_set_displayname( $user, $displayname )->then( sub {
         matrix_create_user_on_server( $user->http,
            displayname => $searching_displayname
         );
      })->then( sub {
         ( $searching_user ) = @_;

         matrix_create_room( $user,
            preset => "private_chat",
         );
      })->then( sub {
         matrix_get_user_dir_synced( $searching_user, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            and die "user in list";

         Future->done( 1 );
      });
   };

multi_test "User joining then leaving public room appears and dissappears from directory",
   requires => [ local_user_fixtures( 2 ) ],

   check => sub {
      my ( $creator, $user ) = @_;

      log_if_fail "User interested in", $user->user_id;

      my $room_id;

      my $displayname = generate_random_displayname();

      matrix_set_displayname( $user, $displayname )
      ->then( sub {
         matrix_create_room( $creator,
            preset => "public_chat",
         );
      })->then( sub {
         ( $room_id ) = @_;

         log_if_fail "Room interested in", $room_id;

         matrix_get_user_dir_synced( $user, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            and die "user in list";

         pass "User initially not in directory";

         matrix_join_room( $user, $room_id );
      })->then( sub {
         matrix_get_user_dir_synced( $user, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            or die "user not in list";

         pass "User appears in directory after join";

         matrix_leave_room( $user, $room_id );
      })->then( sub {
         matrix_get_user_dir_synced( $user, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            and die "user in list";

         pass "User not in directory after leaving room";

         Future->done( 1 );
      });
   };

foreach my $type (qw( join_rules history_visibility )) {
   multi_test "Users appear/disappear from directory when $type are changed",
      requires => [ local_user_fixtures( 2 ) ],

      # this test is currently flaky due to a synapse bug
      bug => "synapse#2306",

      check => sub {
         my ( $creator, $user ) = @_;

         log_if_fail "creator", $creator->user_id;
         log_if_fail "user", $user->user_id;

         my $room_id;

         my $displayname = generate_random_displayname();

         log_if_fail "display_name", $displayname;

         matrix_set_displayname( $user, $displayname )
         ->then( sub {
            matrix_create_room( $creator,
               preset => "private_chat", invite => [ $user->user_id ],
            );
         })->then( sub {
            ( $room_id ) = @_;

            log_if_fail "Room", $room_id;

            matrix_join_room( $user, $room_id );
         })->then( sub {
            matrix_get_user_dir_synced( $user, $displayname );
         })->then( sub {
            my ( $body ) = @_;
            my $results = $body->{results};

            log_if_fail "Results", $results;

            any { $_->{user_id} eq $user->user_id } @$results
               and die "user in list";

            pass "User initially not in directory";

            if( $type eq "join_rules" ) {
               matrix_put_room_state( $creator, $room_id,
                  type    => "m.room.join_rules",
                  content => { join_rule => "public" },
               );
            }
            else {
               matrix_put_room_state( $creator, $room_id,
                  type    => "m.room.history_visibility",
                  content => { history_visibility => "world_readable" },
               );
            }
         })->then( sub {
            matrix_get_user_dir_synced( $user, $displayname );
         })->then( sub {
            my ( $body ) = @_;
            my $results = $body->{results};

            log_if_fail "Results", $results;

            any { $_->{user_id} eq $user->user_id } @$results
               or die "user not in list";

            pass "User appears in directory after $type set to public";

            if( $type eq "join_rules" ) {
               matrix_put_room_state( $creator, $room_id,
                  type    => "m.room.join_rules",
                  content => { join_rule => "invite" },
               );
            }
            else {
               matrix_put_room_state( $creator, $room_id,
                  type    => "m.room.history_visibility",
                  content => { history_visibility => "shared" },
               );
            }
         })->then( sub {
            matrix_get_user_dir_synced( $user, $displayname );
         })->then( sub {
            my ( $body ) = @_;
            my $results = $body->{results};

            log_if_fail "Results", $results;

            any { $_->{user_id} eq $user->user_id } @$results
               and die "user in list";

            pass "User not in directory after $type set to private";

            Future->done( 1 );
         });
      };
}


multi_test "Users stay in directory when join_rules are changed but history_visibility is world_readable",
   requires => [ local_user_fixtures( 2 ) ],

   # this test is currently flaky due to a synapse bug
   bug => "synapse#2306",

   check => sub {
      my ( $creator, $user ) = @_;

      my $room_id;

      my $displayname = generate_random_displayname();

      matrix_set_displayname( $user, $displayname )
      ->then( sub {
         matrix_create_room( $creator,
            preset => "private_chat", invite => [ $user->user_id ],
         );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user, $room_id );
      })->then( sub {
         matrix_get_user_dir_synced( $user, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            and die "user in list";

         pass "User initially not in directory";

         matrix_put_room_state( $creator, $room_id,
            type    => "m.room.join_rules",
            content => { join_rule => "public" },
         );
      })->then( sub {
         matrix_put_room_state( $creator, $room_id,
            type    => "m.room.history_visibility",
            content => { history_visibility => "world_readable" },
         );
      })->then( sub {
         matrix_get_user_dir_synced( $user, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            or die "user not in list";

         pass "User appears in directory after join_rules set to public";

         matrix_put_room_state( $creator, $room_id,
            type    => "m.room.join_rules",
            content => { join_rule => "invite" },
         );
      })->then( sub {
         matrix_get_user_dir_synced( $user, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            or die "user not in list";

         pass "User still in directory after join_rules set to invite";

         matrix_put_room_state( $creator, $room_id,
            type    => "m.room.history_visibility",
            content => { history_visibility => "shared" },
         );
      })->then( sub {
         matrix_get_user_dir_synced( $user, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            and die "user in list";

         pass "User not in directory after history_visibility set to shared";

         Future->done( 1 );
      });
   };

test "User in remote room doesn't appear in user directory after server left room",
   requires => [ local_user_fixture(), remote_user_fixture() ],

   check => sub {
      my ( $creator, $remote ) = @_;

      my $room_id;

      my $displayname = generate_random_displayname();

      matrix_set_displayname( $creator, $displayname )
      ->then( sub {
         matrix_create_room( $creator,
            preset => "public_chat", invite => [ $remote->user_id ],
         );
      })->then( sub {
         ( $room_id ) = @_;

         log_if_fail "room_id", $room_id;

         matrix_join_room( $remote, $room_id );
      })->then( sub {
         matrix_get_user_dir_synced( $remote, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $creator->user_id } @$results
            or die "user not in list";

         matrix_leave_room( $remote, $room_id );
      })->then( sub {
         matrix_get_user_dir_synced( $remote, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $creator->user_id } @$results
            and die "user in list";

         Future->done( 1 );
      });
   };

test "User directory correctly update on display name change",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      my $room_id;
      my $searching_user;

      my $displayname = generate_random_displayname();
      my $second_displayname = generate_random_displayname();
      my $searching_displayname = generate_random_displayname();

      matrix_set_displayname( $user, $displayname )
      ->then( sub {
         matrix_create_user_on_server( $user->http,
            displayname => $searching_displayname
         );
      }) -> then( sub {
         ( $searching_user ) = @_;

         log_if_fail "First displayname", $displayname;

         matrix_create_room( $user,
            preset => "public_chat",
         );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $searching_user, $room_id );
      })->then( sub {
         matrix_get_user_dir_synced( $user, $displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            or die "user not in list";

         matrix_set_displayname( $user, $second_displayname );
      })->then( sub {
         log_if_fail "Second displayname", $second_displayname;

         matrix_get_user_dir_synced( $user, $second_displayname );
      })->then( sub {
         my ( $body ) = @_;
         my $results = $body->{results};

         log_if_fail "Results", $results;

         any { $_->{user_id} eq $user->user_id } @$results
            or die "user not in list";

         Future->done( 1 );
      });
   };


push our @EXPORT, qw( generate_random_displayname matrix_get_user_dir_synced );

sub generate_random_displayname
{
   join "", map { chr 65 + rand 26 } 1 .. 20;
}


# Get the user directory after a change has been made. This creates two new users
# and then polls the user directory until one sees the other. This is to get around the
# fact that the user directory gets updated asynchronously.
sub matrix_get_user_dir_synced
{
   my ( $user, $search_term ) = @_;

   my $new_user;
   my $searching_user;
   my $room_id;

   my $random_id = join "", map { chr 65 + rand 26 } 1 .. 20;
   my $searching_random_id = join "", map { chr 65 + rand 26 } 1 .. 20;

   matrix_create_user_on_server( $user->http,
      displayname => $random_id
   )->then( sub {
      ( $new_user ) = @_;

      matrix_create_user_on_server( $user->http,
         displayname => $searching_random_id
      );
   }) -> then( sub {
      ( $searching_user ) = @_;

      matrix_create_room( $new_user,
         preset => "public_chat",
      );
   })->then( sub {
      ( $room_id ) = @_;

      matrix_join_room( $searching_user, $room_id );
   })->then( sub {
      repeat_until_true {
         do_request_json_for( $searching_user,
            method  => "POST",
            uri     => "/r0/user_directory/search",
            content => {
               search_term => $random_id,
            }
         )->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( results ) );
            assert_json_list( my $results = $body->{results} );

            Future->done( any { $_->{user_id} eq $new_user->user_id } @$results );
         });
      };
   })->then( sub {
      do_request_json_for( $user,
         method  => "POST",
         uri     => "/r0/user_directory/search",
         content => {
            search_term => $search_term,
         }
      );
   });
}
