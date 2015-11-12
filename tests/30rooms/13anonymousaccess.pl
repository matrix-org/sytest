use Future::Utils qw( try_repeat_until_success );

test "Anonymous user cannot view non-world-readable rooms",
   requires => [ anonymous_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_set_room_history_visibility( $user, $room_id, "shared" );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id, body => "mice" )
      })->then( sub {
         do_request_json_for( $anonymous_user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => "1",
               dir   => "b",
            },
         )
      })->main::expect_http_403;
   };

test "Anonymous user can view world-readable rooms",
   requires => [ anonymous_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id, body => "mice" )
      })->then( sub {
         do_request_json_for( $anonymous_user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => "2",
               dir   => "b",
            },
         )
      });
   };

test "Anonymous user cannot call /events on non-world_readable room",
   requires => [ anonymous_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "mice" )
      })->then( sub {
         do_request_json_for( $anonymous_user,
            method => "GET",
            uri    => "/api/v1/rooms/${room_id}/messages",
            params => {
               limit => "2",
               dir   => "b",
            },
         )
      })->main::expect_http_403;
   };

test "Anonymous user can call /events on world_readable room",
   requires => [ anonymous_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
      })->then( sub {
         Future->needs_all(
            delay( 0.05 )->then( sub {
               matrix_send_room_text_message( $user, $room_id, body => "mice" );
            }),

            do_request_json_for( $anonymous_user,
               method => "GET",
               uri    => "/api/v1/events",
               params => {
                  limit => "2",
                  dir   => "b",
               },
            )->main::expect_http_400->then( sub {
               do_request_json_for( $anonymous_user,
                  method => "GET",
                  uri    => "/api/v1/events",
                  params => {
                     limit   => "2",
                     dir     => "b",
                     room_id => $room_id,
                  },
               )
            })->then( sub {
               my ( $body ) = @_;

               require_json_keys( $body, qw( chunk ) );
               $body->{chunk} >= 1 or die "Want at least one event";
               my $event = $body->{chunk}[0];
               require_json_keys( $event, qw( content ) );
               my $content = $event->{content};
               require_json_keys( $content, qw( body ) );
               $content->{body} eq "mice" or die "Want content body to be mice";

               Future->done( 1 );
            }),
         );
      });
   };

test "Anonymous user doesn't get events before room made world_readable",
   requires => [ anonymous_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         Future->needs_all(
            delay( 0.05 )->then( sub {
               matrix_send_room_text_message( $user, $room_id, body => "private" )->then(sub {
                  matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
               })->then( sub {
                  matrix_send_room_text_message( $user, $room_id, body => "public" );
               });
            }),

            # The client is allowed to see exactly two events, the
            # m.room.history_visibility event and the public message.
            # The server is free to return these in separate calls to
            # /events, so we try at most two times to get the events we expect.
            check_events( $anonymous_user, $room_id )
            ->then(sub {
               Future->done( 1 );
            }, sub {
               check_events( $anonymous_user, $room_id );
            }),
         );
      });
   };

test "Anonymous users can get state for non-world_readable rooms",
   requires => [ local_user_and_room_fixtures(), anonymous_user_fixture() ],

   do => sub {
      my ( $user, $room_id ) = @_;

      matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
   },

   check => sub {
      my ( $user, $room_id, $anonymous_user ) = @_;

      do_request_json_for( $anonymous_user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state",
      );
   };

test "Anonymous users can get individual state for world_readable rooms",
   requires => [ local_user_and_room_fixtures(), anonymous_user_fixture() ],

   do => sub {
      my ( $user, $room_id ) = @_;

      matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
   },

   check => sub {
      my ( $user, $room_id, $anonymous_user ) = @_;

      do_request_json_for( $anonymous_user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.member/".$user->user_id,
      );
   };

test "Anonymous users can join guest_access rooms",
   requires => [ local_user_and_room_fixtures(), anonymous_user_fixture() ],

   do => sub {
      my ( $user, $room_id ) = @_;

      matrix_set_room_guest_access( $user, $room_id, "can_join" );
   },

   check => sub {
      my ( undef, $room_id, $anonymous_user ) = @_;

      matrix_join_room( $anonymous_user, $room_id );
   };

test "Anonymous users can send messages to guest_access rooms if joined",
   requires => [ local_user_and_room_fixtures(), anonymous_user_fixture() ],

   do => sub {
      my ( $user, $room_id, $anonymous_user ) = @_;

      matrix_set_room_guest_access( $user, $room_id, "can_join" )
      ->then( sub {
         matrix_join_room( $anonymous_user, $room_id )
      })->then( sub {
         matrix_send_room_text_message( $anonymous_user, $room_id, body => "sup" );
      })->then(sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",

            params => { limit => 1, dir => "b" },
         )->then( sub {
            my ( $body ) = @_;
            log_if_fail "Body:", $body;

            require_json_keys( $body, qw( start end chunk ));
            require_json_list( my $chunk = $body->{chunk} );

            scalar @$chunk == 1 or
               die "Expected one message";

            my ( $event ) = @$chunk;

            require_json_keys( $event, qw( type room_id user_id content ));

            $event->{user_id} eq $anonymous_user->user_id or
               die "expected user_id to be ".$anonymous_user->user_id;

            $event->{content}->{body} eq "sup" or
               die "content to be sup";

            Future->done(1);
         });
      })
   };

test "Anonymous users cannot send messages to guest_access rooms if not joined",
   requires => [ local_user_and_room_fixtures(), anonymous_user_fixture() ],

   do => sub {
      my ( $user, $room_id, $anonymous_user ) = @_;

      matrix_set_room_guest_access( $user, $room_id, "can_join" )
      ->then( sub {
         matrix_send_room_text_message( $anonymous_user, $room_id, body => "sup" );
      })->main::expect_http_403;
   };

sub check_events
{
   my ( $user, $room_id ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/api/v1/events",
      params => {
         limit   => "3",
         dir     => "b",
         room_id => $room_id,
      },
   )->then( sub {
      my ( $body ) = @_;

      log_if_fail "Body", $body;

      require_json_keys( $body, qw( chunk ) );
      @{ $body->{chunk} } >= 1 or die "Want at least one event";
      @{ $body->{chunk} } < 3 or die "Want at most two events";

      my $found = 0;
      foreach my $event ( @{ $body->{chunk} } ) {
         next if all { $_ ne "content" } keys %{ $event };
         next if all { $_ ne "body" } keys %{ $event->{content} };
         $found = 1 if $event->{content}->{body} eq "public";
         die "Should not have found private" if $event->{content}->{body} eq "private";
      }

      Future->done( $found );
   }),
}

test "Anonymous users are kicked from guest_access rooms on revocation of guest_access",
   requires => [ local_user_and_room_fixtures(), anonymous_user_fixture() ],

   do => sub {
      my ( $user, $room_id, $anonymous_user ) = @_;

      matrix_set_room_guest_access( $user, $room_id, "can_join" )
      ->then( sub {
         matrix_join_room( $anonymous_user, $room_id );
      })->then( sub {
         matrix_get_room_membership( $user, $room_id, $anonymous_user );
      })->then( sub {
         my ( $membership ) = @_;

         $membership eq "join" or die("want membership to be join but is $membership");

         matrix_set_room_guest_access( $user, $room_id, "forbidden" );
      })->then( sub {
         matrix_get_room_membership( $user, $room_id, $anonymous_user );
      })->then( sub {
         my ( $membership ) = @_;

         $membership eq "leave" or die("want membership to be leave but is $membership");

         Future->done( 1 );
      });
   };

test "Anonymous user can set display names",
   requires => [ anonymous_user_fixture(), local_user_and_room_fixtures() ],

   do => sub {
      my ( $anonymous_user, $user, $room_id ) = @_;

      my $displayname_uri = "/api/v1/profile/:user_id/displayname";

      matrix_set_room_guest_access( $user, $room_id, "can_join" )->then( sub {
         matrix_join_room( $anonymous_user, $room_id );
      })->then( sub {
         do_request_json_for( $anonymous_user,
            method => "GET",
            uri    => $displayname_uri,
      )})->then( sub {
         my ( $body ) = @_;

         defined $body->{displayname} and die "Didn't expect displayname";

         do_request_json_for( $anonymous_user,
            method  => "PUT",
            uri     => $displayname_uri,
            content => {
               displayname => "creeper",
            },
      )})->then( sub {
         Future->needs_all(
            do_request_json_for( $anonymous_user,
               method => "GET",
               uri    => $displayname_uri,
            )->then( sub {
               my ( $body ) = @_;
               $body->{displayname} eq "creeper" or die "Wrong displayname";
               Future->done( 1 );
            }),
            do_request_json_for( $anonymous_user,
               method => "GET",
               uri    => "/api/v1/rooms/$room_id/state/m.room.member/:user_id",
            )->then( sub {
               my ( $body ) = @_;
               $body->{displayname} eq "creeper" or die "Wrong displayname";
               Future->done( 1 );
            }),
         );
      });
   };

test "Anonymous users are kicked from guest_access rooms on revocation of guest_access over federation",
   requires => [ local_user_fixture(), remote_user_fixture(), anonymous_user_fixture() ],

   do => sub {
      my ( $local_user, $remote_user, $anonymous_user ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $local_user, $remote_user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_change_room_powerlevels( $local_user, $room_id, sub {
            my ( $levels ) = @_;
            $levels->{users}{ $remote_user->user_id } = 50;
         })->then( sub {
            matrix_set_room_guest_access( $local_user, $room_id, "can_join" )
         })->then( sub {
            matrix_join_room( $remote_user, $room_id );
         })->then( sub {
            matrix_join_room( $anonymous_user, $room_id );
         })->then( sub {
            matrix_get_room_membership( $local_user, $room_id, $anonymous_user );
         })->then( sub {
            my ( $membership ) = @_;

            $membership eq "join" or die("want membership to be join but is $membership");

            Future->needs_all(
               await_event_for( $local_user, sub {
                  my ( $event ) = @_;
                  return $event->{type} eq "m.room.guest_access" && $event->{content}->{guest_access} eq "forbidden";
               }),

               # This may fail a few times if the power level event hasn't federated yet.
               # So we retry.
               try_repeat_until_success( sub {
                  matrix_set_room_guest_access( $remote_user, $room_id, "forbidden" );
               }),
            );
         })->then( sub {
            matrix_get_room_membership( $local_user, $room_id, $anonymous_user );
         })->then( sub {
            my ( $membership ) = @_;

            $membership eq "leave" or die("want membership to be leave but is $membership");

            Future->done( 1 );
         });
      })
   };

test "GET /publicRooms lists rooms",
   requires => [qw( first_api_client ), local_user_fixture() ],

   check => sub {
      my ( $http, $user ) = @_;

      Future->needs_all(
         matrix_create_room( $user,
            visibility => "public",
            room_alias_name => "listingtest0",
         ),

         matrix_create_room( $user,
            visibility => "public",
            room_alias_name => "listingtest1",
         )->then( sub {
            my ( $room_id ) = @_;

            matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
         }),

         matrix_create_room( $user,
            visibility => "public",
            room_alias_name => "listingtest2",
         )->then( sub {
            my ( $room_id ) = @_;

            matrix_set_room_history_visibility( $user, $room_id, "invited" );
         }),

         matrix_create_room( $user,
            visibility => "public",
            room_alias_name => "listingtest3",
         )->then( sub {
            my ( $room_id ) = @_;

            matrix_set_room_guest_access( $user, $room_id, "can_join" );
         }),

         matrix_create_room( $user,
            visibility => "public",
            room_alias_name => "listingtest4",
         )->then( sub {
            my ( $room_id ) = @_;

            Future->needs_all(
               matrix_set_room_guest_access( $user, $room_id, "can_join" ),
               matrix_set_room_history_visibility( $user, $room_id, "world_readable" ),
            );
         }),
      )->then( sub {
         $http->do_request_json(
            method => "GET",
            uri    => "/api/v1/publicRooms",
      )})->then( sub {
         my ( $body ) = @_;

         log_if_fail "publicRooms", $body;

         require_json_keys( $body, qw( start end chunk ));
         require_json_list( $body->{chunk} );

         my %seen = (
            listingtest0 => 0,
            listingtest1 => 0,
            listingtest2 => 0,
            listingtest3 => 0,
            listingtest4 => 0,
         );

         foreach my $room ( @{ $body->{chunk} } ) {
            my $aliases = $room->{aliases};
            require_json_boolean( my $world_readable = $room->{world_readable} );
            require_json_boolean( my $guest_can_join = $room->{guest_can_join} );

            foreach my $alias ( @{$aliases} ) {
               if( $alias =~ m/^\Q#listingtest0:/ ) {
                  $seen{listingtest0} = !$world_readable && !$guest_can_join;
               }
               elsif( $alias =~ m/^\Q#listingtest1:/ ) {
                  $seen{listingtest1} = $world_readable && !$guest_can_join;
               }
               elsif( $alias =~ m/^\Q#listingtest2:/ ) {
                  $seen{listingtest2} = !$world_readable && !$guest_can_join;
               }
               elsif( $alias =~ m/^\Q#listingtest3:/ ) {
                  $seen{listingtest3} = !$world_readable && $guest_can_join;
               }
               elsif( $alias =~ m/^\Q#listingtest4:/ ) {
                  $seen{listingtest4} = $world_readable && $guest_can_join;
               }
            }
         }

         foreach my $key (keys %seen ) {
            $seen{$key} or die "Wrong for $key";
         }

         Future->done(1);
      });
   };

sub anonymous_user_fixture
{
   fixture(
      requires => [qw( first_api_client )],

      setup => sub {
         my ( $http ) = @_;

         $http->do_request_json(
            method  => "POST",
            uri     => "/v2_alpha/register",
            content => {},
            params  => {
               kind => "guest",
            },
         )->then( sub {
            my ( $body ) = @_;
            my $access_token = $body->{access_token};

            Future->done( User( $http, $body->{user_id}, $access_token, undef, undef, [], undef ) );
         });
   })
}

push our @EXPORT, qw( matrix_set_room_guest_access matrix_set_room_history_visibility matrix_get_room_membership );

sub matrix_set_room_guest_access
{
   my ( $user, $room_id, $guest_access ) = @_;

   matrix_put_room_state( $user, $room_id,
      type    => "m.room.guest_access",
      content => { guest_access => $guest_access }
   );
}

sub matrix_set_room_history_visibility
{
   my ( $user, $room_id, $history_visibility ) = @_;

   matrix_put_room_state( $user, $room_id,
      type    => "m.room.history_visibility",
      content => { history_visibility => $history_visibility }
   );
}

sub matrix_get_room_membership
{
   my ( $checking_user, $room_id, $tested_user ) = @_;

   matrix_get_room_state( $checking_user, $room_id,
      type => "m.room.member",
      state_key => $tested_user->user_id,
   )->then(
      sub {
         my ( $event ) = @_;

         Future->done( $event->{membership} );
      },
      sub {
         Future->done( "leave" );
      }
   );
}
