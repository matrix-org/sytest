use Future::Utils qw( repeat );

test "/whois",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      my $user;

      # Register a user, rather than using a fixture, because we want to very
      # tightly control the actions taken by that user.
      # Conceivably this API may change based on the number of API calls the
      # user made, for instance.
      matrix_register_user( $http, "admin" )
      ->then( sub {
         ( $user ) = @_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/admin/whois/".$user->user_id,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( devices user_id ) );
         assert_eq( $body->{user_id}, $user->user_id, "user_id" );
         assert_json_object( $body->{devices} );

         foreach my $value ( values %{ $body->{devices} } ) {
            assert_json_keys( $value, "sessions" );
            assert_json_list( $value->{sessions} );
            assert_json_keys( $value->{sessions}[0], "connections" );
            assert_json_list( $value->{sessions}[0]{connections} );
            assert_json_keys( $value->{sessions}[0]{connections}[0], qw( ip last_seen user_agent ) );
         }

         Future->done( 1 );
      });
   };

test "/purge_history",
   requires => [ local_admin_fixture(), local_user_and_room_fixtures() ],

   do => sub {
      my ( $admin, $user, $room_id ) = @_;

      my $last_event_id;

      matrix_put_room_state( $user, $room_id,
         type    => "m.room.name",
         content => { name => "A room name" },
      )->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         ( $last_event_id ) = @_;

         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/admin/purge_history/$room_id/$last_event_id",
            content => {}
         )->main::expect_http_403;  # Must be server admin
      })->then( sub {
         matrix_sync( $user )
      })->then( sub {
         do_request_json_for( $admin,
            method  => "POST",
            uri     => "/r0/admin/purge_history/$room_id/$last_event_id",
            content => {}
         )
      })->then( sub {
         # Test that /sync with an existing token still works.
         matrix_sync_again( $user )
      })->then( sub {
         # Test that an initial /sync has the correct data.
         matrix_sync( $user )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body->{rooms}{join}, $room_id );
         my $room =  $body->{rooms}{join}{$room_id};

         log_if_fail( "Room", $room->{timeline}{events} );

         # The only message event should be the last one.
         all {
            $_->{type} ne "m.room.message" || $_->{event_id} eq $last_event_id
         } @{ $room->{timeline}{events} } or die "Expected no message events";

         # Ensure we still see the state.
         foreach my $expected_type( qw(
            m.room.create
            m.room.member
            m.room.power_levels
            m.room.name
         ) ) {
            any { $_->{type} eq $expected_type } @{ $room->{state}{events} }
               or die "Expected state event of type $expected_type";
         }

         Future->done( 1 );
      })
   };

test "Can backfill purged history",
   requires => [ local_admin_fixture(), local_user_and_room_fixtures(),
                 remote_user_fixture(), qw( can_paginate_room_remotely ) ],

   do => sub {
      my ( $admin, $user, $room_id, $remote_user ) = @_;

      my @event_ids;
      my $last_event_id;

      matrix_invite_user_to_room( $user, $remote_user, $room_id )
      ->then( sub {
         matrix_join_room( $remote_user, $room_id )
      })->then( sub {
         matrix_put_room_state( $user, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         )
      })->then( sub {
         Future->needs_all(
            matrix_sync( $user ),
            matrix_sync( $remote_user )
         )
      })->then( sub {
         # Send half the messages as the local user...
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $user, $room_id,
               body => "Message $msgnum",
            )->on_done( sub { push @event_ids, $_[0]; } )
         }, foreach => [ 0 .. 4 ])
      })->then( sub {
         my ( $last_local_id ) = @_;

         # Wait until both users see the last event
         Future->needs_all(
            await_message_in_room( $user, $room_id, $last_local_id ),
            await_message_in_room( $remote_user, $room_id, $last_local_id )
         )
      })->then( sub {
         # ... and half as the remote. This is useful to esnre that both local
         # and remote events are handled correctly.
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $remote_user, $room_id,
               body => "Message $msgnum",
            )->on_done( sub { push @event_ids, $_[0]; } )
         }, foreach => [ 5 .. 9 ])
      })->then( sub {
         ( $last_event_id ) = @_;

         log_if_fail "last_event_id", $last_event_id;

         # Wait until both users see the last event
         Future->needs_all(
            await_message_in_room( $user, $room_id, $last_event_id ),
            await_message_in_room( $remote_user, $room_id, $last_event_id )
         )
      })->then( sub {
         do_request_json_for( $admin,
            method  => "POST",
            uri     => "/r0/admin/purge_history/$room_id/$last_event_id",
            content => {}
         )
      })->then( sub {
         matrix_sync( $user )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body->{rooms}{join}, $room_id );
         my $room =  $body->{rooms}{join}{$room_id};

         log_if_fail( "Room timeline", $room->{timeline}{events} );

         # The only message event should be the last one.
         all {
            $_->{type} ne "m.room.message" || $_->{event_id} eq $last_event_id
         } @{ $room->{timeline}{events} } or die "Expected no message events";

         # Ensure we still see the state.
         foreach my $expected_type( qw(
            m.room.create
            m.room.member
            m.room.power_levels
            m.room.name
         ) ) {
            any { $_->{type} eq $expected_type } @{ $room->{state}{events} }
               or die "Expected state event of type $expected_type";
         }

         my $prev_batch = $room->{timeline}{prev_batch};

         my @missing_event_ids = grep { $_ ne $last_event_id } @event_ids;

         # Keep paginating untill we see all the old messages.
         repeat( sub {
            log_if_fail "prev_batch", $prev_batch;
            matrix_get_room_messages( $user, $room_id,
               limit => 20,
               from => $prev_batch,
            )->on_done( sub {
               my ( $body ) = @_;

               log_if_fail( "Pagination result", $body );

               $prev_batch ne $body->{end} or die "Pagination token did not change";

               $prev_batch = $body->{end};

               foreach my $event ( @{ $body->{chunk} } ) {
                  @missing_event_ids = grep {
                     $_ ne $event->{event_id}
                  } @missing_event_ids;
               }

               log_if_fail "Missing", \@missing_event_ids;
            })
         }, while => sub { scalar @missing_event_ids > 0 });
      });
   };


sub await_message_in_room
{
   my ( $user, $room_id, $event_id ) = @_;

   my $user_id = $user->user_id;

   repeat( sub {
      matrix_sync_again( $user, timeout => 500 )
      ->then( sub {
         my ( $body ) = @_;

         log_if_fail "Sync for $user_id", $body;

         Future->done( any {
            $_->{event_id} eq $event_id
         } @{ $body->{rooms}{join}{$room_id}{timeline}{events} } )
      })
   }, until => sub {
      $_[0]->failure or $_[0]->get
   })->on_done( sub {
      log_if_fail "Found event $event_id for $user_id";
   })
}
