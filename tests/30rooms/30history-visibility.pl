use JSON qw( encode_json );
use URI::Escape qw( uri_escape );
use Future::Utils qw( repeat );

use constant { YES => 1, NO => !1 };

my %PERMITTED_ACTIONS = (
   # Map from the m.room.history_visibility state to a list of booleans,
   #   indicating what actions are/are not permitted
   world_readable => {
      see_without_join => YES,
      see_before_join  => YES,
      see_after_invite => YES,
   },
   shared => {
      see_without_join => NO,
      see_before_join  => YES,
      see_after_invite => YES,
   },
   invited => {
      see_without_join => NO,
      see_before_join  => NO,
      see_after_invite => YES,
   },
   joined => {
      see_without_join => NO,
      see_before_join  => NO,
      see_after_invite => NO,
   },
   default => { # shared by default
      see_without_join => NO,
      see_before_join  => YES,
      see_after_invite => YES,
   },
);

sub test_history_visibility
{
   my ( $user_fixture, $user_type, $visibility, $permitted ) = @_;

   test( "m.room.history_visibility == \"$visibility\" allows/forbids "
          ."appropriately for $user_type users",
      requires => [ local_user_and_room_fixtures(), $user_fixture->(), ],

      do => sub {
         my ( $creator, $room_id, $joiner ) = @_;

         my $before_join_event_id;
         my $after_invite_event_id;

         matrix_set_room_history_visibility( $creator, $room_id, $visibility )
         ->then( sub {
            matrix_set_room_guest_access_synced($creator, $room_id, "can_join");
         })->then( sub {
            matrix_send_room_text_message_synced( $creator, $room_id, body => "Before join" )
               ->on_done( sub { ( $before_join_event_id ) = @_ } )
         })->then( sub {
            my $rq = matrix_get_room_messages( $joiner, $room_id, limit => 10 );
            if( $permitted->{see_without_join} ) {
                $rq->then( sub {
                    my ( $body ) = @_;
                    my %visible_events = map { $_->{event_id} => $_ } @{ $body->{chunk} };

                    assert_eq( exists $visible_events{$before_join_event_id}, 1,
                               "visibility without join'" );
                    Future->done();
                 });
             } else {
                $rq->followed_by( \&expect_4xx_or_empty_chunk );
             }
         })->then( sub {
            matrix_invite_user_to_room_synced( $creator, $joiner, $room_id );
         })->then( sub {
            matrix_send_room_text_message_synced( $creator, $room_id, body => "After invite" )
               ->on_done( sub { ( $after_invite_event_id ) = @_ } )
         })->then( sub {
            matrix_join_room_synced( $joiner, $room_id );
         })->then( sub {
            matrix_get_room_messages( $joiner, $room_id, limit => 10 )
         })->then( sub {
            my ( $body ) = @_;
            my %visible_events = map { $_->{event_id} => $_ } @{ $body->{chunk} };

            assert_eq( exists $visible_events{$before_join_event_id},
               $permitted->{see_before_join},
               "visibility of 'before_join'" );

            assert_eq( exists $visible_events{$after_invite_event_id},
               $permitted->{see_after_invite},
               "visibility of 'after_invite'" );

            Future->done(1);
         });
      },
   );
}

foreach my $i (
   [ "Guest", sub { guest_user_fixture( with_events => 1 ) } ],
   [ "Real", sub { local_user_fixture( with_events => 1 ) } ]
) {
   my ( $name, $fixture ) = @$i;

   # /messages

   foreach my $visibility (qw( world_readable shared invited joined default )) {
      test_history_visibility( $fixture, $name, $visibility, $PERMITTED_ACTIONS{$visibility} );
  }

   # /events

   foreach my $visibility (qw( shared invited joined default )) {
      test(
         "$name non-joined user cannot call /events on $visibility room",

         requires => [ $fixture->(), local_user_and_room_fixtures() ],

         do => sub {
            my ( $nonjoined_user, $creator_user, $room_id ) = @_;

            matrix_set_room_history_visibility( $creator_user, $room_id, $visibility )
            ->then( sub {
               matrix_send_room_text_message( $creator_user, $room_id, body => "mice" )
            })->then( sub {
               matrix_get_events( $nonjoined_user, room_id => $room_id );
            })->followed_by( \&expect_4xx_or_empty_chunk );
         },
      );
   }

   test(
      "$name non-joined user can call /events on world_readable room",

      requires => [ $fixture->(), local_user_fixture( with_events => 1 ), local_user_fixture( with_events => 1 ) ],

      do => sub {
         my ( $nonjoined_user, $user, $user_not_in_room ) = @_;

         my ( $room_id, $sent_event_id );

         matrix_create_and_join_room( [ $user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_set_room_history_visibility_synced( $user, $room_id, "world_readable" );
         })->then( sub {
            matrix_initialsync_room( $nonjoined_user, $room_id )
         })->then( sub {
            Future->needs_all(
               matrix_send_room_text_message( $user, $room_id, body => "mice" )
               ->on_done( sub {
                  ( $sent_event_id ) = @_;
               }),

               await_event_not_history_visibility_or_presence_for( $nonjoined_user, $room_id, [] )
               ->then( sub {
                  my ( $event ) = @_;

                  assert_json_keys( $event, qw( content ) );
                  my $content = $event->{content};
                  assert_json_keys( $content, qw( body ) );
                  assert_eq( $content->{body}, "mice", "content body" );

                  Future->done(1);
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

                  await_event_not_history_visibility_or_presence_for( $nonjoined_user, $room_id, [ $user ] )->then( sub {
                     my ( $event ) = @_;

                     assert_eq( $event->{type}, "m.presence",
                        "event type" );
                     assert_eq( $event->{content}{user_id}, $user->user_id,
                        "event content.user_id" );

                     Future->done(1);
                  }),
               ),
            })->then( sub {
               my ( $stream_token ) = @_;

               Future->needs_all(
                  do_request_json_for( $user,
                     method  => "POST",
                     uri     => "/r0/rooms/$room_id/receipt/m.read/${ \uri_escape( $sent_event_id ) }",
                     content => {},
                  ),

                  await_event_not_history_visibility_or_presence_for( $nonjoined_user, $room_id, [] )->then( sub {
                     my ( $event ) = @_;

                     assert_eq( $event->{type}, "m.receipt",
                        "event type" );
                     assert_ok( $event->{content}{$sent_event_id}{"m.read"}{ $user->user_id },
                        "receipt event ID for user" );

                     Future->done(1);
                  }),
               );
            })->then( sub {
               my ( $stream_token ) = @_;

               Future->needs_all(
                  do_request_json_for( $user,
                     method  => "PUT",
                     uri     => "/r0/rooms/$room_id/typing/:user_id",
                     content => {
                        typing => JSON::true,
                        timeout => 5000,
                     },
                  ),

                  await_event_not_history_visibility_or_presence_for( $nonjoined_user, $room_id, [] )->then( sub {
                     my ( $event ) = @_;

                     assert_eq( $event->{type}, "m.typing",
                        "event type" );
                     assert_eq( $event->{room_id}, $room_id,
                        "event room_id" );
                     assert_eq( $event->{content}{user_ids}[0], $user->user_id,
                        "event content user_ids[0]" );

                     Future->done(1);
                  }),
               );
            });
         });
      },
   );

   test(
      "$name non-joined user doesn't get events before room made world_readable",

      requires => [ $fixture->(), local_user_fixture( with_events => 1 ) ],

      do => sub {
         my ( $nonjoined_user, $user ) = @_;

         my $room_id;

         matrix_create_and_join_room( [ $user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_send_room_text_message( $user, $room_id, body => "private" );
         })->then( sub {
            matrix_set_room_history_visibility_synced( $user, $room_id, "world_readable" );
         })->then( sub {
            Future->needs_all(
               matrix_send_room_text_message( $user, $room_id, body => "public" ),

               # The client is allowed to see exactly two events, the
               # m.room.history_visibility event and the public message.
               # The server is free to return these in separate calls to
               # /events, so we try at most two times to get the events we expect.
               check_events( $nonjoined_user, $room_id )
               ->then( sub {
                  Future->done(1);
               }, sub {
                  check_events( $nonjoined_user, $room_id );
               }),
            );
         });
      },
   );

   # /state

   test(
      "$name non-joined users can get state for world_readable rooms",

      requires => [ local_user_and_room_fixtures(), $fixture->() ],

      do => sub {
         my ( $user, $room_id ) = @_;

         matrix_set_room_history_visibility_synced( $user, $room_id, "world_readable" );
      },

      check => sub {
         my ( $user, $room_id, $nonjoined_user ) = @_;

         do_request_json_for( $nonjoined_user,
            method => "GET",
            uri    => "/r0/rooms/$room_id/state",
         );
      },
   );

   test(
      "$name non-joined users can get individual state for world_readable rooms",

      requires => [ local_user_and_room_fixtures(), $fixture->() ],

      do => sub {
         my ( $user, $room_id ) = @_;

         matrix_set_room_history_visibility_synced( $user, $room_id, "world_readable" );
      },

      check => sub {
         my ( $user, $room_id, $nonjoined_user ) = @_;

         do_request_json_for( $nonjoined_user,
            method => "GET",
            uri    => "/r0/rooms/$room_id/state/m.room.member/".$user->user_id,
         );
      },
   );

   # room /initialSync

   test(
      "$name non-joined users cannot room initalSync for non-world_readable rooms",

      requires => [ guest_user_fixture(), local_user_fixture() ],

      do => sub {
         my ( $non_joined_user, $creating_user ) = @_;

         my $room_id;

         matrix_create_and_join_room( [ $creating_user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_send_room_text_message( $creating_user, $room_id, body => "private" )
         })->then( sub {
            matrix_initialsync_room( $non_joined_user, $room_id )
               ->main::expect_http_403;
         });
      },
   );

   test(
      "$name non-joined users can room initialSync for world_readable rooms",

      requires => [ guest_user_fixture( with_events => 1 ), local_user_fixture( with_events => 1 ) ],

      do => sub {
         my ( $syncing_user, $creating_user ) = @_;

         my $room_id;

         matrix_create_and_join_room( [ $creating_user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_send_room_text_message( $creating_user, $room_id, body => "private" )
         })->then( sub {
            matrix_set_room_history_visibility_synced( $creating_user, $room_id, "world_readable" );
         })->then( sub {
            matrix_send_room_text_message_synced( $creating_user, $room_id, body => "public" );
         })->then( sub {
            matrix_initialsync_room( $syncing_user, $room_id );
         })->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( room_id state messages presence ));
            assert_json_keys( $body->{messages}, qw( chunk start end ));
            assert_json_list( $body->{messages}{chunk} );
            assert_json_list( $body->{state} );

            log_if_fail "room initialSync body", $body;

            my $chunk = $body->{messages}{chunk};

            @$chunk == 2 or die "Wrong number of chunks";
            assert_eq( $chunk->[0]->{type}, "m.room.history_visibility", "event 0 type" );
            assert_eq( $chunk->[0]->{content}->{history_visibility}, "world_readable", "history_visibility content" );
            assert_eq( $chunk->[1]->{type}, "m.room.message", "event 1 type" );
            assert_eq( $chunk->[1]->{content}->{body}, "public", "message content body" );

            Future->done(1);
         });
      },
   );

   test(
      "$name non-joined users can get individual state for world_readable rooms after leaving",

      requires => [ local_user_and_room_fixtures(), $fixture->() ],

      do => sub {
         my ( $user, $room_id, $nonjoined_user ) = @_;

         Future->needs_all(
            matrix_set_room_history_visibility_synced( $user, $room_id, "world_readable" ),
            matrix_set_room_guest_access_synced( $user, $room_id, "can_join" ),
         )->then( sub {
            matrix_join_room( $nonjoined_user, $room_id );
         })->then( sub {
            matrix_leave_room( $nonjoined_user, $room_id );
         })->then( sub {
            do_request_json_for( $nonjoined_user,
               method => "GET",
               uri    => "/r0/rooms/$room_id/state/m.room.member/".$user->user_id,
            );
         });
      },
   );

   test(
      "$name non-joined users cannot send messages to guest_access rooms if not joined",

      requires => [ local_user_and_room_fixtures(), $fixture->() ],

      do => sub {
         my ( $user, $room_id, $nonjoined_user ) = @_;

         matrix_set_room_guest_access_synced( $user, $room_id, "can_join" )
         ->then( sub {
            matrix_send_room_text_message( $nonjoined_user, $room_id, body => "sup" )
               ->main::expect_http_403;
         });
      },
   );

   foreach my $visibility ( qw( world_readable shared invited joined default )) {
      test("$name users can sync from $visibility guest_access rooms if joined",
         requires => [ local_user_and_room_fixtures(), $fixture->() ],

         do => sub {
            my ( $user, $room_id, $joining_user ) = @_;

            matrix_set_room_guest_access_synced( $user, $room_id, "can_join" )
            ->then( sub {
               matrix_send_room_text_message( $user, $room_id, body => "shared" );
            })->then( sub {
               matrix_set_room_history_visibility( $user, $room_id, $visibility );
            })->then( sub {
               matrix_send_room_text_message( $user, $room_id, body => "pre_join" );
            })->then( sub {
               matrix_join_room( $joining_user, $room_id );
            })->then( sub {
               matrix_send_room_text_message_synced( $user, $room_id, body => "post_join" );
            })->then( sub {
               matrix_sync( $joining_user );
            })->then( sub {
               my ( $body ) = @_;

               my $room = $body->{rooms}{join}{$room_id};
               assert_json_keys( $room, qw( timeline state ephemeral ));
               assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));

               # look at the last four events
               my @chunk = @{ $room->{timeline}->{events} };
               splice @chunk, 0, -4;

               log_if_fail "messages", \@chunk;

               # if the history visibility was shared or world_readable, we
               # expect to see the event before we joined; if not, we expect to
               # see the event before the history visibility was changed.
               # We always expect to see the history visibility change.
               if( $PERMITTED_ACTIONS{$visibility}->{see_before_join} ) {
                  if ( $visibility eq "shared" || $visibility eq "default" ) {
                     assert_eq( $chunk[0]->{type}, "m.room.message", "event 0 type" );
                  } else {
                     assert_eq( $chunk[0]->{type}, "m.room.history_visibility", "event 0 type" );
                  }
                  assert_eq( $chunk[1]->{type}, "m.room.message", "event 1 type" );
                  assert_eq( $chunk[1]->{content}->{body}, "pre_join", "message 1 content body" );
               }
               else {
                  assert_eq( $chunk[0]->{type}, "m.room.message", "event 0 type" );
                  assert_eq( $chunk[0]->{content}->{body}, "shared", "message 0 content body" );
                  assert_eq( $chunk[1]->{type}, "m.room.history_visibility", "event 1 type" );
               }
               assert_eq( $chunk[2]->{type}, "m.room.member", "event 1 type" );
               assert_eq( $chunk[3]->{type}, "m.room.message", "event 2 type" );
               assert_eq( $chunk[3]->{content}->{body}, "post_join", "message 2 content body" );

               Future->done(1);
            });
         },
      );
   }
}


test "Only see history_visibility changes on boundaries",
   requires => [ local_user_and_room_fixtures(), local_user_fixture( with_events => 1 ) ],

   do => sub {
      my ( $user, $room_id, $joining_user ) = @_;

      matrix_set_room_history_visibility_synced( $user, $room_id, "joined" )
      ->then( sub {
         matrix_send_room_text_message( $user, $room_id, body => "1" );
      })->then( sub {
         matrix_set_room_history_visibility_synced( $user, $room_id, "invited" )
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id, body => "2" );
      })->then( sub {
         matrix_set_room_history_visibility_synced( $user, $room_id, "shared" )
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id, body => "3" );
      })->then( sub {
         matrix_join_room_synced( $joining_user, $room_id );
      })->then( sub {
         matrix_sync( $joining_user );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));

         # look at the last four events
         my @chunk = @{ $room->{timeline}->{events} };
         splice @chunk, 0, -4;

         log_if_fail "messages", \@chunk;

         assert_eq( $chunk[0]->{type}, "m.room.history_visibility", "event 0 type" );
         assert_eq( $chunk[0]->{content}->{history_visibility}, "joined", "event 0 content body" );
         assert_eq( $chunk[1]->{type}, "m.room.history_visibility", "event 1 type" );
         assert_eq( $chunk[1]->{content}->{history_visibility}, "shared", "event 1 content body" );
         assert_eq( $chunk[2]->{type}, "m.room.message", "event 2 type" );
         assert_eq( $chunk[2]->{content}->{body}, "3", "message 2 content body" );
         assert_eq( $chunk[3]->{type}, "m.room.member", "event 3 type" );

         Future->done(1);
      });
   };

test "Backfill works correctly with history visibility set to joined",
   requires => [ magic_local_user_and_room_fixtures( with_alias => 1), local_user_fixture(), remote_user_fixture() ],

   do => sub {
      my ( $user, $room_id, $room_alias, $another_user, $remote_user, $room_alias_name ) = @_;

      matrix_set_room_history_visibility_synced( $user, $room_id, "joined" )
      ->then( sub {
         # Send some m.room.message that the remote server will not be able to see
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $user, $room_id, body => "Message $msgnum" );
         }, foreach => [ 1 .. 10 ]);
      })->then( sub {
         # We now send a state event to ensure they're correctly handled in
         # backfill. This was a bug in synapse (c.f. #1943)
         matrix_join_room( $another_user, $room_alias );
      })->then( sub {
         matrix_send_room_text_message( $user, $room_id, body => "2" );
      })->then( sub {
         matrix_join_room( $remote_user, $room_alias );
      })->then( sub {
         matrix_get_room_messages( $remote_user, $room_id, limit => 10 )
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "messages body", $body;

         my $chunk = $body->{chunk};

         # Check we can't see any of the message events
         foreach my $event ( @$chunk ) {
            $event->{type} eq "m.room.message"
               and die "Remote user should not see any message events";
         }

         Future->done( 1 );
      })
   };

sub check_events
{
   my ( $user, $room_id ) = @_;

   matrix_get_events( $user, limit => 3, dir => "b", room_id => $room_id )
   ->then( sub {
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

push our @EXPORT, qw( await_event_not_history_visibility_or_presence_for );

sub await_event_not_history_visibility_or_presence_for
{
   my ( $user, $room_id, $allowed_users, %params ) = @_;
   await_event_for( $user,
      room_id => $room_id,
      filter  => sub {
         my ( $event ) = @_;

         return 0 if defined $event->{type} and $event->{type} eq "m.room.history_visibility";

         # Include all events where the type is not m.presence.
         # If the type is m.presence, then only include it if it is for one of
         # the allowed users
         return ((not $event->{type} eq "m.presence") or
            any { $event->{content}{user_id} eq $_->user_id } @$allowed_users);
      },
      %params,
   )->on_done( sub {
      my ( $event ) = @_;
      log_if_fail "event", $event
   });
}
