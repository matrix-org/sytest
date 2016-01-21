use Future::Utils qw( try_repeat_until_success repeat );
use JSON qw( encode_json );

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
         matrix_get_room_messages( $anonymous_user, $room_id, limit => "1" )
      })->followed_by( \&expect_4xx_or_empty_chunk );
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
         matrix_get_room_messages( $anonymous_user, $room_id, limit => "2" )
      });
   };

test "Anonymous user cannot call /events globally",
   requires => [ anonymous_user_fixture() ],

   do => sub {
      my ( $anonymous_user ) = @_;

      do_request_json_for( $anonymous_user,
         method => "GET",
         uri    => "/api/v1/events",
      )->followed_by( \&expect_4xx_or_empty_chunk );
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
            uri    => "/api/v1/events",
            params => {
               room_id => $room_id,
            },
         );
      })->followed_by( \&expect_4xx_or_empty_chunk );
   };

sub await_event_not_presence_for
{
   my ( $user, $room_id, $allowed_users ) = @_;
   await_event_for( $user,
      room_id => $room_id,
      filter  => sub {
         my ( $event ) = @_;

         # Include all events where the type is not m.presence.
         # If the type is m.presence, then only include it if it is for one of
         # the allowed users
         return ((not $event->{type} eq "m.presence") or
            any { $event->{content}{user_id} eq $_->user_id } @$allowed_users);
      },
   )->on_done( sub {
      my ( $event ) = @_;
      log_if_fail "event", $event
   });
}


test "Real user can call /events on world_readable room",
   requires => [ local_user_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ),
                 local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $real_user, $user, $user_not_in_room ) = @_;

      my ( $room_id );

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
      })->then( sub {
         flush_events_for( $real_user )
      })->then( sub {
         Future->needs_all(
            matrix_send_room_text_message( $user, $room_id, body => "mice" ),

            await_event_not_presence_for( $real_user, $room_id, [] )
            ->then( sub {
               my ( $event ) = @_;

               assert_json_keys( $event, qw( content ) );
               my $content = $event->{content};
               assert_json_keys( $content, qw( body ) );
               $content->{body} eq "mice" or die "Want content body to be mice";

               Future->done( 1 );
            }),
         );
      });
   };

test "Real user can call /events on another world_readable room",
   requires => [ local_user_fixture( with_events => 0 ),
                 local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $real_user, $user ) = @_;

      my ( $room_id1, $room_id2 );

      Future->needs_all(
         matrix_create_and_join_room( [ $user ] ),
         matrix_create_and_join_room( [ $user ] ),
      )->then( sub {
         ( $room_id1, $room_id2 ) = @_;

         Future->needs_all(
            matrix_set_room_history_visibility( $user, $room_id1, "world_readable" ),
            matrix_set_room_history_visibility( $user, $room_id2, "world_readable" ),
         )
      })->then( sub {
         flush_events_for( $real_user )
      })->then( sub {
         Future->needs_all(
            matrix_send_room_text_message( $user, $room_id1, body => "moose" ),
            await_event_not_presence_for( $real_user, $room_id1, [] ),
         );
      })->then( sub {
         flush_events_for( $real_user )
      })->then( sub {
         Future->needs_all(
            delay( 0.1 )->then( sub {
               matrix_send_room_text_message( $user, $room_id2, body => "mice" );
            }),

            await_event_not_presence_for( $real_user, $room_id2, [] )
            ->then( sub {
               my ( $event ) = @_;

               assert_json_keys( $event, qw( content ) );
               my $content = $event->{content};
               assert_json_keys( $content, qw( body ) );
               $content->{body} eq "mice" or die "Want content body to be mice";

               Future->done( 1 );
            }),
         );
      });
   };


test "Real user's /events on world_readable room is woken up",
   requires => [ local_user_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ),
                 local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $real_user, $user, $user_not_in_room ) = @_;

      my ( $room_id );

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
      })->then( sub {
         flush_events_for( $real_user )
      })->then( sub {
         Future->needs_all(
            matrix_send_room_text_message( $user, $room_id, body => "mice" ),

            await_event_not_presence_for( $real_user, $room_id, [] )
            ->then( sub {
               my ( $event ) = @_;

               assert_json_keys( $event, qw( content ) );
               my $content = $event->{content};
               assert_json_keys( $content, qw( body ) );
               $content->{body} eq "mice" or die "Want content body to be mice";

               Future->done( 1 );
            }),
         );
      });
   };



test "Anonymous user can call /events on world_readable room",
   requires => [ anonymous_user_fixture(), local_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user, $user_not_in_room ) = @_;

      my ( $room_id, $sent_event_id );

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
      })->then( sub {
         matrix_initialsync_room( $anonymous_user, $room_id )
      })->then( sub {
         Future->needs_all(
            matrix_send_room_text_message( $user, $room_id, body => "mice" )
            ->on_done( sub {
               ( $sent_event_id ) = @_;
            }),

            await_event_not_presence_for( $anonymous_user, $room_id, [] )
            ->then( sub {
               my ( $event ) = @_;

               assert_json_keys( $event, qw( content ) );
               my $content = $event->{content};
               assert_json_keys( $content, qw( body ) );
               $content->{body} eq "mice" or die "Want content body to be mice";

               Future->done( 1 );
            }),
         )->then( sub {
            my ( $stream_token ) = @_;

            Future->needs_all(
               matrix_set_presence_status( $user_not_in_room, "online",
                  status_msg => "Worshiping lemurs' tails",
               ),
               matrix_set_presence_status( $user, "online",
                  status_msg => "Worshiping lemurs' tails",
               ),

               await_event_not_presence_for( $anonymous_user, $room_id, [ $user ] )->then( sub {
                  my ( $event ) = @_;

                  assert_eq( $event->{type}, "m.presence",
                     "event type" );
                  assert_eq( $event->{content}{user_id}, $user->user_id,
                     "event content.user_id" );

                  Future->done( 1 );
               }),
            ),
         })->then( sub {
            my ( $stream_token ) = @_;

            Future->needs_all(
               do_request_json_for( $user,
                  method  => "POST",
                  uri     => "/v2_alpha/rooms/$room_id/receipt/m.read/$sent_event_id",
                  content => {},
               ),

               await_event_not_presence_for( $anonymous_user, $room_id, [] )->then( sub {
                  my ( $event ) = @_;

                  assert_eq( $event->{type}, "m.receipt",
                     "event type" );
                  assert_ok( $event->{content}{$sent_event_id}{"m.read"}{ $user->user_id },
                     "receipt event ID for user" );

                  Future->done( 1 );
               }),
            );
         })->then( sub {
            my ( $stream_token ) = @_;

            Future->needs_all(
               do_request_json_for( $user,
                  method  => "PUT",
                  uri     => "/api/v1/rooms/$room_id/typing/:user_id",
                  content => {
                     typing => JSON::true,
                     timeout => 5000,
                  },
               ),

               await_event_not_presence_for( $anonymous_user, $room_id, [] )->then( sub {
                  my ( $event ) = @_;

                  assert_eq( $event->{type}, "m.typing",
                     "event type" );
                  assert_eq( $event->{room_id}, $room_id,
                     "event room_id" );
                  assert_eq( $event->{content}{user_ids}[0], $user->user_id,
                     "event content user_ids[0]" );

                  Future->done( 1 );
               }),
            );
         });
      });
   };

test "Annonymous user can call /sync on a world readable room",
   requires => [ anonymous_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user ) = @_;

      my ( $room_id, $sent_event_id );

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
      })->then( sub {
         matrix_set_room_guest_access( $user, $room_id, "can_join" );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id, body => "mice" );
      })->then( sub {
         ( $sent_event_id ) = @_;

         matrix_join_room( $anonymous_user, $room_id );
      })->then( sub {

         matrix_sync( $anonymous_user, filter => encode_json({
            room => {
               rooms => [ $room_id ],
               ephemeral => { types => [] },
               state => { types => [] },
               timeline => { types => ["m.room.message"] },
            },
            presence => { types => [] }
         }));
      })->then( sub {
         my ( $sync_body ) = @_;

         assert_json_object( my $room = $sync_body->{rooms}{join}{$room_id} );
         assert_json_list( my $events = $room->{timeline}{events} );
         assert_eq( $events->[0]{event_id}, $sent_event_id, 'event id' );

         Future->done( 1 );
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

         matrix_send_room_text_message( $user, $room_id, body => "private" );
      })->then( sub {
         matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
      })->then( sub {
         Future->needs_all(
            matrix_send_room_text_message( $user, $room_id, body => "public" ),

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

test "Anonymous users can get state for world_readable rooms",
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

test "Real users can get state for world_readable rooms",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $user, $room_id ) = @_;

      matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
   },

   check => sub {
      my ( $user, $room_id, $non_joined_user ) = @_;

      do_request_json_for( $non_joined_user,
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

test "Anonymous user cannot room initalSync for non-world_readable rooms",
   requires => [ anonymous_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "private" )
      })->then( sub {
         matrix_initialsync_room( $anonymous_user, $room_id )
            ->main::expect_http_403;
      });
   };


test "Anonymous user can room initialSync for world_readable rooms",
   requires => [ anonymous_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "private" )
      })->then(sub {
         matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id, body => "public" );
      })->then( sub {
         matrix_initialsync_room( $anonymous_user, $room_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id state messages presence ));
         assert_json_keys( $body->{messages}, qw( chunk start end ));
         assert_json_list( $body->{messages}{chunk} );
         assert_json_list( $body->{state} );

         log_if_fail "room initialSync body", $body;

         my $chunk = $body->{messages}{chunk};

         @{ $chunk } == 2 or die "Wrong number of chunks";
         $chunk->[0]->{type} eq "m.room.history_visibility" or die "Want m.room.history_visibility";
         $chunk->[0]->{content}->{history_visibility} eq "world_readable" or die "Wrong history_visibility value";
         $chunk->[1]->{type} eq "m.room.message" or die "Want m.room.message";
         $chunk->[1]->{content}->{body} eq "public" or die "Wrong message body";

         Future->done( 1 );
      });
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
         matrix_get_room_messages( $user, $room_id, limit => 1 )->then( sub {
            my ( $body ) = @_;
            log_if_fail "Body:", $body;

            assert_json_keys( $body, qw( start end chunk ));
            assert_json_list( my $chunk = $body->{chunk} );

            scalar @$chunk == 1 or
               die "Expected one message";

            my ( $event ) = @$chunk;

            assert_json_keys( $event, qw( type room_id user_id content ));

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
         matrix_send_room_text_message( $anonymous_user, $room_id, body => "sup" )
            ->main::expect_http_403;
      });
   };

test "Anonymous users can get individual state for world_readable rooms after leaving",
   requires => [ local_user_and_room_fixtures(), anonymous_user_fixture() ],

   do => sub {
      my ( $user, $room_id, $anonymous_user ) = @_;

      Future->needs_all(
         matrix_set_room_history_visibility( $user, $room_id, "world_readable" ),
         matrix_set_room_guest_access( $user, $room_id, "can_join" ),
      )->then( sub {
         matrix_join_room( $anonymous_user, $room_id );
      })->then( sub {
         matrix_leave_room( $anonymous_user, $room_id );
      })->then( sub {
         do_request_json_for( $anonymous_user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state/m.room.member/".$user->user_id,
         );
      });
   };

test "Annonymous user calling /events doesn't tightloop",
   requires => [ anonymous_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $anonymous_user, $user ) = @_;

      my ( $room_id );

      matrix_create_and_join_room( [ $user ] )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
      })->then( sub {
         do_request_json_for( $anonymous_user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/initialSync",
         );
      })->then( sub {
         my ( $sync_body ) = @_;
         my $sync_from = $sync_body->{messages}->{end};

         repeat( sub {
            my ( undef, $f ) = @_;

            my $end_token = $f ? $f->get->{end} : $sync_from;

            log_if_fail "Events body", $f ? $f->get : undef;

            get_events_no_timeout( $anonymous_user, $room_id, $end_token );
         }, foreach => [ 0 .. 5 ], until => sub {
            my ( $res ) = @_;
            $res->failure or not @{ $res->get->{chunk} };
         });
      })->then( sub {
          my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_empty_list( $body->{chunk} );

         Future->done(1);
      });
   };


sub get_events_no_timeout
{
   my ( $user, $room_id, $from_token ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/api/v1/events",
      params => {
         room_id => $room_id,
         timeout => 0,
         from => $from_token,
      },
   );
}


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

      assert_json_keys( $body, qw( chunk ) );
      @{ $body->{chunk} } >= 1 or die "Want at least one event";
      @{ $body->{chunk} } < 3 or die "Want at most two events";

      my $found = 0;
      foreach my $event ( @{ $body->{chunk} } ) {
         next if !exists $event->{content};
         next if !exists $event->{content}{body};

         $found = 1 if $event->{content}{body} eq "public";
         die "Should not have found private" if $event->{content}{body} eq "private";
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
               await_event_for( $local_user, filter => sub {
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

test "Anonymous user can upgrade to fully featured user",
   requires => [ local_user_and_room_fixtures(), anonymous_user_fixture(), $main::API_CLIENTS[0] ],

   do => sub {
      my ( $creator, $room_id, $anonymous_user, $http ) = @_;

      my ( $local_part ) = $anonymous_user->user_id =~ m/^@([^:]+):/g;
      $http->do_request_json(
         method  => "POST",
         uri     => "/r0/register",
         content => {
            username => $local_part,
            password => "SIR_Arthur_David",
            guest_access_token => $anonymous_user->access_token,
         },
      )->followed_by( sub {
         $http->do_request_json(
            method  => "POST",
            uri     => "/r0/register",
            content => {
               username     => $local_part,
               password     => "SIR_Arthur_David",
               guest_access_token => $anonymous_user->access_token,
               auth         => {
                  type => "m.login.dummy",
               },
            },
         )
      })->on_done( sub {
         my ( $body ) = @_;
         $anonymous_user->access_token = $body->{access_token};
      })
   },

   check => sub {
      my ( undef, $room_id, $anonymous_user ) = @_;

      matrix_join_room( $anonymous_user, $room_id );
   };

test "Anonymous user cannot upgrade other users",
   requires => [ local_user_and_room_fixtures(), anonymous_user_fixture(), anonymous_user_fixture(), $main::API_CLIENTS[0] ],

   do => sub {
      my ( $creator, $room_id, $anonymous_user1, $anonymous_user2, $http ) = @_;

      my ( $local_part1 ) = $anonymous_user1->user_id =~ m/^@([^:]+):/g;
      $http->do_request_json(
         method  => "POST",
         uri     => "/r0/register",
         content => {
            username => $local_part1,
            password => "SIR_Arthur_David",
            guest_access_token => $anonymous_user2->access_token,
         },
      )->main::expect_http_4xx;
   };


test "GET /publicRooms lists rooms",
   requires => [ $main::API_CLIENTS[0], local_user_fixture() ],

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

         assert_json_keys( $body, qw( start end chunk ));
         assert_json_list( $body->{chunk} );

         my %seen = (
            listingtest0 => 0,
            listingtest1 => 0,
            listingtest2 => 0,
            listingtest3 => 0,
            listingtest4 => 0,
         );

         foreach my $room ( @{ $body->{chunk} } ) {
            my $aliases = $room->{aliases};
            assert_json_boolean( my $world_readable = $room->{world_readable} );
            assert_json_boolean( my $guest_can_join = $room->{guest_can_join} );

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

test "GET /publicRooms includes avatar URLs",
   requires => [ $main::API_CLIENTS[0], local_user_fixture() ],

   check => sub {
      my ( $http, $user ) = @_;

      Future->needs_all(
         matrix_create_room( $user,
            visibility => "public",
            room_alias_name => "nonworldreadable",
         )->then( sub {
            my ( $room_id ) = @_;

            matrix_put_room_state( $user, $room_id,
               type      => "m.room.avatar",
               state_key => "",
               content   => {
                  url => "https://example.com/ruffed.jpg",
               }
            );
         }),

         matrix_create_room( $user,
            visibility => "public",
            room_alias_name => "worldreadable",
         )->then( sub {
            my ( $room_id ) = @_;

            Future->needs_all(
               matrix_set_room_history_visibility( $user, $room_id, "world_readable" ),
               matrix_put_room_state( $user, $room_id,
                  type      => "m.room.avatar",
                  state_key => "",
                  content   => {
                     url => "https://example.com/ringtails.jpg",
                  }
               ),
            );
         }),
      )->then( sub {
         $http->do_request_json(
            method => "GET",
            uri    => "/api/v1/publicRooms",
      )})->then( sub {
         my ( $body ) = @_;

         log_if_fail "publicRooms", $body;

         assert_json_keys( $body, qw( start end chunk ));
         assert_json_list( $body->{chunk} );

         my %seen = (
            worldreadable    => 0,
            nonworldreadable => 0,
         );

         foreach my $room ( @{ $body->{chunk} } ) {
            my $aliases = $room->{aliases};

            foreach my $alias ( @{$aliases} ) {
               if( $alias =~ m/^\Q#worldreadable:/ ) {
                  assert_json_keys( $room, qw( avatar_url ) );
                  assert_eq( $room->{avatar_url}, "https://example.com/ringtails.jpg", "avatar_url" );
                  $seen{worldreadable} = 1;
               }
               elsif( $alias =~ m/^\Q#nonworldreadable:/ ) {
                  assert_json_keys( $room, qw( avatar_url ) );
                  assert_eq( $room->{avatar_url}, "https://example.com/ruffed.jpg", "avatar_url" );
                  $seen{nonworldreadable} = 1;
               }
            }
         }

         foreach my $key (keys %seen ) {
            $seen{$key} or die "Didn't see $key";
         }

         Future->done(1);
      });
   };

sub anonymous_user_fixture
{
   fixture(
      requires => [ $main::API_CLIENTS[0] ],

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

            Future->done( User( $http, $body->{user_id}, $access_token, undef, undef, undef, [], undef ) );
         });
   })
}

push our @EXPORT, qw( matrix_set_room_guest_access matrix_get_room_membership );

sub matrix_set_room_guest_access
{
   my ( $user, $room_id, $guest_access ) = @_;

   matrix_put_room_state( $user, $room_id,
      type    => "m.room.guest_access",
      content => { guest_access => $guest_access }
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
         my ( $content ) = @_;

         Future->done( $content->{membership} );
      },
      sub {
         Future->done( "leave" );
      }
   );
}

sub ignore_presence_for
{
   my ( $ignored_users, @events ) = @_;

   return [ grep {
      my $event = $_;
      not(
         $event->{type} eq "m.presence" and
            any { $event->{content}{user_id} eq $_->user_id } @$ignored_users
      )
   } @events ];
}

sub expect_4xx_or_empty_chunk
{
   my ( $f ) = @_;

   $f->then( sub {
      my ( $body ) = @_;

      log_if_fail "Body", $body;

      assert_json_keys( $body, qw( chunk ) );
      assert_json_list( $body->{chunk} );
      die "Want list to be empty" if @{ $body->{chunk} };

      Future->done( 1 );
   },
   http => sub {
      my ( undef, undef, $response ) = @_;

      log_if_fail "HTTP Response", $response;

      $response->code >= 400 and $response->code < 500 or die "want 4xx";

      Future->done( 1 );
   });
}
