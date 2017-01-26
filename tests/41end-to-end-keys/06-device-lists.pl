use Future::Utils qw( try_repeat_until_success );

test "Local device key changes appear in v2 /sync",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my ( $room_id );

      matrix_create_room( $user1 )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         do_request_json_for( $user2,
            method  => "POST",
            uri     => "/unstable/keys/upload",
            content => {
               device_keys => {
                  user_id => $user2->user_id,
                  device_id => $user2->device_id,
               },
               one_time_keys => {
                  "my_algorithm:my_id_1", "my+base64+key"
               }
            }
         )
      })->then( sub {
         matrix_sync_again( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, "device_lists" );
         my $device_lists = $body->{device_lists};

         log_if_fail "device_lists", $device_lists;

         assert_json_keys( $device_lists, "changed" );
         my $changed = $device_lists->{changed};

         any { $user2->user_id eq $_ } @{ $changed }
            or die "user not in changed list";

         Future->done(1);
      });
   };


test "Local new device changes appear in v2 /sync",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my ( $room_id );

      matrix_create_room( $user1 )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         matrix_login_again_with_user( $user2 )
      })->then( sub {
         matrix_sync_again( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, "device_lists" );
         my $device_lists = $body->{device_lists};

         log_if_fail "device_lists", $device_lists;

         assert_json_keys( $device_lists, "changed" );
         my $changed = $device_lists->{changed};

         any { $user2->user_id eq $_ } @{ $changed }
            or die "user not in changed list";

         Future->done(1);
      });
   };

test "Local delete device changes appear in v2 /sync",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my ( $room_id );

      matrix_create_room( $user1 )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         matrix_delete_device( $user2, $user2->device_id, {
             auth => {
                 type     => "m.login.password",
                 user     => $user2->user_id,
                 password => $user2->password,
             }
         });
      })->then( sub {
         matrix_sync_again( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, "device_lists" );
         my $device_lists = $body->{device_lists};

         log_if_fail "device_lists", $device_lists;

         assert_json_keys( $device_lists, "changed" );
         my $changed = $device_lists->{changed};

         any { $user2->user_id eq $_ } @{ $changed }
            or die "user not in changed list";

         Future->done(1);
      });
   };

test "Local update device changes appear in v2 /sync",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my ( $room_id );

      matrix_create_room( $user1 )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         matrix_set_device_display_name( $user2, $user2->device_id, "wibble");
      })->then( sub {
         matrix_sync_again( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, "device_lists" );
         my $device_lists = $body->{device_lists};

         log_if_fail "device_lists", $device_lists;

         assert_json_keys( $device_lists, "changed" );
         my $changed = $device_lists->{changed};

         any { $user2->user_id eq $_ } @{ $changed }
            or die "user not in changed list";

         Future->done(1);
      });
   };


test "Can query remote device keys using POST after notificaiton",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my $room_id;

      matrix_create_room( $user1 )->then( sub {
         ( $room_id ) = @_;

         matrix_invite_user_to_room( $user1, $user2, $room_id )
      })->then( sub {
         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         matrix_put_e2e_keys( $user2 )
      })->then( sub {
         matrix_set_device_display_name( $user2, $user2->device_id, "test display name" ),
      })->then( sub {
         try_repeat_until_success( sub {
            matrix_sync_again( $user1, timeout => 1000 )
            ->then( sub {
               my ( $body ) = @_;

               assert_json_keys( $body, "device_lists" );
               my $device_lists = $body->{device_lists};

               log_if_fail "device_lists", $device_lists;

               assert_json_keys( $device_lists, "changed" );
               my $changed = $device_lists->{changed};

               any { $user2->user_id eq $_ } @{ $changed }
                  or die "user not in changed list";

               Future->done( 1 )
            })
         })
      })->then( sub {
         do_request_json_for( $user1,
            method  => "POST",
            uri     => "/unstable/keys/query",
            content => {
               device_keys => {
                  $user2->user_id => {}
               }
            }
         )
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $user2->user_id );

         my $alice_keys = $device_keys->{ $user2->user_id };
         assert_json_keys( $alice_keys, $user2->device_id );

         my $alice_device_keys = $alice_keys->{ $user2->device_id };

         # TODO: Check that the content matches what we uploaded.

         assert_eq( $alice_device_keys->{"unsigned"}->{"device_display_name"},
                    "test display name" );

         Future->done(1)
      });
   };
