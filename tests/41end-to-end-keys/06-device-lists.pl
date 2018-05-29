use Future::Utils qw( try_repeat_until_success );

sub is_user_in_changed_list
{
   my ( $user, $body ) = @_;

   return $body->{device_lists} &&
          $body->{device_lists}{changed} &&
          any { $_ eq $user->user_id } @{ $body->{device_lists}{changed} };
}


# returns a Future which resolves to the body of the sync result which contains
# the change notification
sub sync_until_user_in_device_list
{
   my ( $syncing_user, $user_to_wait_for, %params ) = @_;

   my $device_list = $params{device_list} // 'changed';
   my $msg = $params{msg} // 'sync_until_user_in_device_list';

   my $wait_for_id = $user_to_wait_for->user_id;

   $msg = "$msg: waiting for $wait_for_id in $device_list";

   return repeat_until_true {
      matrix_sync_again( $syncing_user, timeout => 1000 )
      ->then( sub {
         my ( $body ) = @_;

         log_if_fail "$msg: body", $body;

         my $res = $body->{device_lists} &&
            $body->{device_lists}{$device_list} &&
            any { $_ eq $wait_for_id } @{ $body->{device_lists}{$device_list} };

         Future->done( $res && $body );
      });
   };
}

test "Local device key changes appear in v2 /sync",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my $room_id;

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
                  user_id   => $user2->user_id,
                  device_id => $user2->device_id,
               },
               one_time_keys => {
                  "my_algorithm:my_id_1" => "my+base64+key"
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

         is_user_in_changed_list( $user2, $body )
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
         repeat_until_true {
            matrix_sync_again( $user1, timeout => 1000 )
            ->then( sub {
               my ( $body ) = @_;

               log_if_fail "Body", $body;

               Future->done(
                  $body->{device_lists} &&
                  $body->{device_lists}{changed} &&
                  any { $_ eq $user2->user_id } @{ $body->{device_lists}{changed} }
               );
            });
         };
      });
   };

test "Local delete device changes appear in v2 /sync",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my $room_id;

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
         sync_until_user_in_device_list( $user1, $user2 );
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
         sync_until_user_in_device_list( $user1, $user2 );
      });
   };


test "Can query remote device keys using POST after notification",
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
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         matrix_set_device_display_name( $user2, $user2->device_id, "test display name" ),
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
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


# Check that when a remote user leaves and rejoins between calls to sync their
# key still comes down in the changes list
test "If remote user leaves room, changes device and rejoins we see update in sync",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $creator, $remote_leaver ) = @_;

      my $room_id;

      matrix_create_room( $creator,
         invite => [ $remote_leaver->user_id ],
      )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $remote_leaver, $room_id );
      })->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         matrix_put_e2e_keys( $remote_leaver )
      })->then( sub {
         sync_until_user_in_device_list( $creator, $remote_leaver );
      })->then( sub {
         matrix_leave_room_synced( $remote_leaver, $room_id )
      })->then( sub {
         matrix_put_e2e_keys( $remote_leaver, device_keys => { updated => "keys" } )
      })->then( sub {
         # It takes a while for the leave to propagate so lets just hammer this
         # endpoint...
         try_repeat_until_success {
            matrix_invite_user_to_room( $creator, $remote_leaver, $room_id )
         }
      })->then( sub {
         matrix_join_room( $remote_leaver, $room_id );
      })->then( sub {
         repeat_until_true {
            matrix_sync_again( $creator, timeout => 1000 )
            ->then( sub {
               my ( $body ) = @_;

               log_if_fail "Second body", $body;

               Future->done( is_user_in_changed_list( $remote_leaver, $body ) );
            })
         };
      });
   };



test "If remote user leaves room we no longer receive device updates",
   requires => [ local_user_fixture(), remote_user_fixture(), remote_user_fixture(),
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $creator, $remote_leaver, $remote2 ) = @_;

      my $room_id;

      matrix_create_room( $creator )->then( sub {
         ( $room_id ) = @_;

         matrix_invite_user_to_room( $creator, $remote_leaver, $room_id )
      })->then( sub {
         matrix_join_room( $remote_leaver, $room_id );
      })->then( sub {
         matrix_invite_user_to_room( $creator, $remote2, $room_id )
      })->then( sub {
         matrix_join_room( $remote2, $room_id );
      })->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         matrix_put_e2e_keys( $remote_leaver )
      })->then( sub {
         matrix_put_e2e_keys( $remote2 )
      })->then( sub {
         sync_until_user_in_device_list( $creator, $remote_leaver );
      })->then( sub {
         matrix_set_device_display_name( $remote_leaver, $remote_leaver->device_id, "test display name" ),
      })->then( sub {
         sync_until_user_in_device_list( $creator, $remote_leaver );
      })->then( sub {
         matrix_leave_room_synced( $remote_leaver, $room_id )
      })->then( sub {
         matrix_put_e2e_keys( $remote_leaver, device_keys => { updated => "keys" } )
      })->then( sub {
         matrix_put_e2e_keys( $remote2, device_keys => { updated => "keys" } )
      })->then( sub {
         sync_until_user_in_device_list( $creator, $remote2 );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Final body", $body;

         any { $_ eq $remote_leaver->user_id } @{ $body->{device_lists}{changed} }
            and die "user2 in changed list after leaving";

         Future->done(1);
      });
   };


test "Local device key changes appear in /keys/changes",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my ( $room_id, $from_token, $to_token );

      matrix_create_room( $user1 )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         $from_token = $body->{next_batch};

         do_request_json_for( $user2,
            method  => "POST",
            uri     => "/unstable/keys/upload",
            content => {
               device_keys => {
                  user_id   => $user2->user_id,
                  device_id => $user2->device_id,
               },
               one_time_keys => {
                  "my_algorithm:my_id_1" => "my+base64+key"
               }
            }
         )
      })->then( sub {
         matrix_sync_again( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         $to_token = $body->{next_batch};

         do_request_json_for( $user1,
            method => "GET",
            uri => "/unstable/keys/changes",
            params => {
               from => $from_token,
               to => $to_token,
            }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( changed) );

         my $changed = $body->{changed};

         any { $user2->user_id eq $_ } @{ $changed }
            or die "user not in changed list";

         Future->done(1);
      });
   };

test "New users appear in /keys/changes",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2  ) = @_;

      my ( $room_id, $from_token, $to_token );

      matrix_create_room( $user1 )->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         $from_token = $body->{next_batch};

         matrix_join_room_synced( $user2, $room_id );
      })->then( sub {
         matrix_sync_again( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         $to_token = $body->{next_batch};

         do_request_json_for( $user1,
            method => "GET",
            uri    => "/unstable/keys/changes",

            params => {
               from => $from_token,
               to   => $to_token,
            }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( changed) );

         my $changed = $body->{changed};

         any { $user2->user_id eq $_ } @{ $changed }
            or die "user not in changed list";

         Future->done(1);
      });
   };


# Check that when a remote user leaves and rejoins between calls to sync their
# key still comes down in the /keys/changes API call
test "If remote user leaves room, changes device and rejoins we see update in /keys/changes",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $creator, $remote_leaver ) = @_;

      my ( $room_id, $from_token, $to_token );

      matrix_create_room( $creator,
         invite => [ $remote_leaver->user_id ],
      )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $remote_leaver, $room_id );
      })->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         matrix_put_e2e_keys( $remote_leaver )
      })->then( sub {
         sync_until_user_in_device_list( $creator, $remote_leaver );
      })->then( sub {
         $from_token = $creator->sync_next_batch;

         matrix_leave_room_synced( $remote_leaver, $room_id )
      })->then( sub {
         matrix_put_e2e_keys( $remote_leaver, device_keys => { updated => "keys" } )
      })->then( sub {
         # It takes a while for the leave to propagate so lets just hammer this
         # endpoint...
         try_repeat_until_success {
            matrix_invite_user_to_room( $creator, $remote_leaver, $room_id )
         }
      })->then( sub {
         matrix_join_room( $remote_leaver, $room_id );
      })->then( sub {
         sync_until_user_in_device_list( $creator, $remote_leaver );
      })->then( sub {
         $to_token = $creator->sync_next_batch;

         do_request_json_for( $creator,
            method => "GET",
            uri    => "/unstable/keys/changes",

            params => {
               from => $from_token,
               to   => $to_token,
            }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( changed ) );

         my $changed = $body->{changed};

         any { $remote_leaver->user_id eq $_ } @{ $changed }
            or die "user not in changed list";

         Future->done(1);
      });
   };

test "Get left notifs in sync and /keys/changes when other user leaves",
   requires => [ local_user_fixtures( 2 ), qw( can_upload_e2e_keys )],

   check => sub {
      my ( $creator, $other_user ) = @_;

      my ( $room_id, $from_token );

      matrix_create_room( $creator,
         invite => [ $other_user->user_id ],
      )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $other_user, $room_id );
      })->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         matrix_put_e2e_keys( $other_user )
      })->then( sub {
         sync_until_user_in_device_list( $creator, $other_user );
      })->then( sub {
         matrix_set_device_display_name( $other_user, $other_user->device_id, "test display name" )
      })->then( sub {
         sync_until_user_in_device_list( $creator, $other_user );
      })->then( sub {
         $from_token = $creator->sync_next_batch;

         matrix_leave_room_synced( $other_user, $room_id )
      })->then( sub {
         sync_until_user_in_device_list(
            $creator, $other_user,
            device_list => "left",
         );
      })->then( sub {
         do_request_json_for( $creator,
            method => "GET",
            uri    => "/unstable/keys/changes",

            params => {
               from => $from_token,
               to   => $creator->sync_next_batch,
            }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( left ) );

         any { $other_user->user_id eq $_ } @{ $body->{left} }
            or die "user not in left list";

         Future->done(1);
      });
   };


test "Get left notifs for other users in sync and /keys/changes when user leaves",
   requires => [ local_user_fixtures( 2 ), qw( can_upload_e2e_keys )],

   check => sub {
      my ( $creator, $other_user ) = @_;

      my ( $room_id, $from_token );

      matrix_create_room( $creator,
         invite => [ $other_user->user_id ],
      )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $other_user, $room_id );
      })->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         matrix_put_e2e_keys( $other_user )
      })->then( sub {
         matrix_set_device_display_name( $other_user, $other_user->device_id, "test display name" )
      })->then( sub {
         sync_until_user_in_device_list( $creator, $other_user );
      })->then( sub {
         $from_token = $creator->sync_next_batch;

         matrix_leave_room_synced( $creator, $room_id )
      })->then( sub {
         sync_until_user_in_device_list(
            $creator, $other_user,
            device_list => "left",
         );
      })->then( sub {
         do_request_json_for( $creator,
            method => "GET",
            uri    => "/unstable/keys/changes",

            params => {
               from => $from_token,
               to   => $creator->sync_next_batch,
            }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( left ) );

         any { $other_user->user_id eq $_ } @{ $body->{left} }
            or die "user not in left list";

         Future->done(1);
      });
   };


test "If user leaves room, remote user changes device and rejoins we see update in /sync and /keys/changes",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $creator, $remote_user ) = @_;

      my ( $room_id, $from_token, $to_token );

      matrix_create_room( $creator,
         invite => [ $remote_user->user_id ],
      )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $remote_user, $room_id );
      })->then( sub {
         matrix_sync( $creator );
      })->then( sub {
         matrix_put_e2e_keys( $remote_user )
      })->then( sub {
         sync_until_user_in_device_list(
            $creator, $remote_user, msg => 'First body',
         );
      })->then( sub {
         $from_token = $creator->sync_next_batch;

         matrix_leave_room_synced( $creator, $room_id )
      })->then( sub {
         matrix_put_e2e_keys( $remote_user, device_keys => { updated => "keys" } )
      })->then( sub {
         # It takes a while for the leave to propagate so lets just hammer this
         # endpoint...
         try_repeat_until_success {
            matrix_invite_user_to_room( $remote_user, $creator, $room_id )
         }
      })->then( sub {
         matrix_join_room( $creator, $room_id );
      })->then( sub {
         sync_until_user_in_device_list(
            $creator, $remote_user, msg => 'Second body',
         );
      })->then( sub {
         $to_token = $creator->sync_next_batch;

         do_request_json_for( $creator,
            method => "GET",
            uri    => "/unstable/keys/changes",

            params => {
               from => $from_token,
               to   => $to_token,
            }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( changed ) );

         my $changed = $body->{changed};

         any { $remote_user->user_id eq $_ } @{ $changed }
            or die "user not in changed list";

         Future->done(1);
      });
   };
