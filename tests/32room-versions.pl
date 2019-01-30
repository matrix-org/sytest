# We test that some basic funcationality works across all room versions
foreach my $version ( qw ( 1 2 3 ) )  {
   multi_test "User can create and send/receive messages in a room with version $version",
      requires => [ local_user_fixture() ],

      check => sub {
         my ( $user ) = @_;

         matrix_create_room_synced(
            $user,
            room_version => $version,
         )->then( sub {
            my ( $room_id, undef, $sync_body ) = @_;

            log_if_fail "sync body", $sync_body;

            my $room =  $sync_body->{rooms}{join}{$room_id};
            my $ev0 = $room->{timeline}{events}[0];

            assert_eq( $ev0->{type}, 'm.room.create',
                     'first event was not m.room.create' );
            assert_json_keys( $ev0->{content}, qw( room_version ));
            assert_eq( $ev0->{content}{room_version}, $version, 'room_version' );

            pass "Can create room";

            matrix_send_room_text_message_synced( $user, $room_id, body => "hello" );
         })->SyTest::pass_on_done( "Can send/receive message in room" );
      };

   # These tests are run against a local and a remote user
   foreach my $user_type ( qw ( local remote ) ) {
      test "$user_type user can join room with version $version",
         requires => [
            local_user_fixture(),
            ( $user_type eq "local" ? local_user_fixture() : remote_user_fixture() ),
            room_alias_name_fixture(),
         ],

         check => sub {
            my ( $user, $joiner, $room_alias_name ) = @_;

            my ( $room_id, $room_alias, $event_id );

            matrix_create_room_synced(
               $user,
               room_version    => $version,
               room_alias_name => $room_alias_name,
            )->then( sub {
               ( $room_id, $room_alias ) = @_;

               matrix_join_room_synced( $joiner, $room_alias );
            })->then( sub {
               matrix_sync( $joiner );
            })->then( sub {
               matrix_send_room_text_message( $user, $room_id,
                  body => "hello",
               );
            })->then( sub {
               ( $event_id ) = @_;

               await_sync( $joiner, check => sub {
                  my ( $body ) = @_;

                  return 0 unless exists $body->{rooms}{join}{$room_id};

                  return $body->{rooms}{join}{$room_id};
               })
            })->then( sub {
               my ( $room ) = @_;

               @{ $room->{timeline}{events} } == 1
                  or die "Expected a single timeline event";

               assert_eq( $room->{timeline}{events}[0]{event_id}, $event_id );

               Future->done( 1 );
            });
         };

      test "User can invite $user_type user to room with version $version",
         requires => [
            local_user_fixture(),
            ( $user_type eq "local" ? local_user_fixture() : remote_user_fixture() ),
         ],

         check => sub {
            my ( $user, $invitee ) = @_;

            my ( $room_id, $event_id );

            matrix_create_room_synced(
               $user,
               room_version => $version,
               preset => "private_chat",
            )->then( sub {
               ( $room_id ) = @_;

               matrix_invite_user_to_room_synced( $user, $invitee, $room_id )
            })->then( sub {
               matrix_join_room_synced( $invitee, $room_id );
            })->then( sub {
               matrix_sync( $invitee );
            })->then( sub {
               matrix_send_room_text_message( $user, $room_id,
                  body => "hello",
               );
            })->then( sub {
               ( $event_id ) = @_;

               await_sync( $invitee, check => sub {
                  my ( $body ) = @_;

                  return 0 unless exists $body->{rooms}{join}{$room_id};

                  return $body->{rooms}{join}{$room_id};
               })
            })->then( sub {
               my ( $room ) = @_;

               @{ $room->{timeline}{events} } == 1
                  or die "Expected a single timeline event";

               assert_eq( $room->{timeline}{events}[0]{event_id}, $event_id );

               Future->done( 1 );
            });
         };
   }

   test "Remote user can backfill in a room with version $version",
      requires => [ local_user_fixture(), remote_user_fixture() ],

      check => sub {
         my ( $user, $remote ) = @_;

         my $room_id;

         matrix_create_room_synced(
            $user,
            room_version => $version,
            invite       => [ $remote->user_id ]
         )->then( sub {
            ( $room_id ) = @_;

            ( repeat {
               matrix_send_room_text_message( $user, $room_id,
                  body => "Message number $_[0]"
               )
            } foreach => [ 1 .. 20 ] );
         })->then( sub {
            matrix_join_room_synced( $remote, $room_id );
         })->then( sub {
            matrix_get_room_messages( $remote, $room_id, limit => 5+1 )
         })->then( sub {
            my ( $body ) = @_;

            my $chunk = $body->{chunk};
            @$chunk == 6 or die "Expected 6 messages";

            Future->done( 1 );
         });
      };

   test "Can reject invites over federation for rooms with version $version",
      requires => [ local_user_fixture(), remote_user_fixture() ],

      check => sub {
         my ( $user, $remote ) = @_;

         my $room_id;

         matrix_create_room_synced(
            $user,
            room_version => $version,
            invite       => [ $remote->user_id ]
         )->then( sub {
            ( $room_id ) = @_;

            await_sync( $remote, check => sub {
               my ( $body ) = @_;

               return 0 unless exists $body->{rooms}{invite}{$room_id};

               return $body->{rooms}{invite}{$room_id};
            })
         })->then( sub {
            matrix_leave_room_synced( $remote, $room_id );
         });
      };
}
