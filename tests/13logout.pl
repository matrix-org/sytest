test "Can logout current device",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my $other_login;

      matrix_login_again_with_user( $user )
      ->then( sub {
         ( $other_login ) = @_;

         # the device list should now have both devices
         do_request_json_for(
            $other_login,
            method => "GET",
            uri => "/r0/devices",
         );
      })->then( sub {
         my ( $devices ) = @_;
         log_if_fail ("/devices response (1): ", $devices);
         my $my_device_id = $user->device_id;
         if ( not any { $_->{device_id} eq $my_device_id } @{ $devices->{devices} } ) {
            die 'Original device $my_device_id did not appear in device list';
         }

         do_request_json_for( $user,
            method => "POST",
             uri    => "/r0/logout",
            content => {},
         )
      })->then( sub {
         # our access token should be invalidated
         repeat_until_true {
            matrix_sync( $user )->main::check_http_code(
               401 => "ok",
               200 => "redo",
            );
         };
      })->then( sub {
         # the device should also have been deleted
         do_request_json_for(
            $other_login,
            method => "GET",
            uri => "/r0/devices",
         );
      })->then( sub {
         my ( $devices ) = @_;
         log_if_fail ("/devices response (2): ", $devices);
         my $my_device_id = $user->device_id;
         if ( any { $_->{device_id} eq $my_device_id } @{ $devices->{devices} } ) {
            die 'Original device $my_device_id still appears in device list';
         }

         matrix_sync( $other_login );
      });
   };


test "Can logout all devices",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my $other_login;

      matrix_login_again_with_user( $user )
      ->then( sub {
         ( $other_login ) = @_;

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/logout/all",
            content => {},
         )
      })->then( sub {
         # our access token should be invalidated
         repeat_until_true {
            matrix_sync( $user )->main::check_http_code(
               401 => "ok",
               200 => "redo",
            );
         };
      })->then( sub {
         # our access token should be invalidated
         repeat_until_true {
            matrix_sync( $other_login )->main::check_http_code(
               401 => "ok",
               200 => "redo",
            );
         };
      });
   };
