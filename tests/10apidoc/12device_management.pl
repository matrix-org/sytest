use Future::Utils qw( try_repeat_until_success );

our @EXPORT = qw( matrix_get_device matrix_set_device_display_name );

sub matrix_get_device {
   my ( $user, $device_id ) = @_;

   return do_request_json_for(
      $user,
      method => "GET",
      uri    => "/unstable/devices/${device_id}",
   );
}

sub matrix_set_device_display_name {
    my ( $user, $device_id, $display_name ) = @_;

    return do_request_json_for(
        $user,
        method => "PUT",
        uri    => "/unstable/devices/${device_id}",
        content => {
            display_name => $display_name,
        },
    );
}

test "GET /device/{deviceId}",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      # easiest way to register a device is to /login with it
      my $DEVICE_ID = "login_device";

      matrix_login_again_with_user(
         $user,
         device_id => $DEVICE_ID,
         initial_device_display_name => "device display",
      )->then( sub {
         matrix_get_device( $user, $DEVICE_ID );
      })->then( sub {
         my ( $device ) = @_;
         assert_json_keys(
            $device,
            qw( device_id user_id display_name ),
         );
         assert_eq( $device->{device_id}, $DEVICE_ID );
         assert_eq( $device->{display_name}, "device display" );
         Future->done( 1 );
      });
   };

test "GET /device/{deviceId} gives a 404 for unknown devices",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for(
         $user,
         method => "GET",
         uri    => "/unstable/devices/unknown_device",
      )->main::expect_http_404;
   };


test "GET /devices",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      # device_id => display_name
      my %DEVICES = (
         "device_1" => "display 1",
         "device_2" => "display 2",
        );

      my @login_futures;
      foreach my $id ( keys( %DEVICES )) {
         my $dev = $DEVICES{$id};
         my $future =
           matrix_login_again_with_user(
              $user,
              device_id => $id,
              initial_device_display_name => $dev,
             );
         push @login_futures, $future;
      }

      Future->needs_all( @login_futures )
      ->then( sub {
          do_request_json_for(
             $user,
             method => "GET",
             uri => "/unstable/devices",
          );
      })->then( sub {
         my ( $devices ) = @_;
         log_if_fail ("/devices response: ", $devices);
         assert_json_keys(
            $devices,
            qw( devices ),
           );
         assert_json_list( $devices->{devices} );

         # check each of the devices we logged in with is returned
         foreach my $id ( keys( %DEVICES )) {
            my $result = first { $_->{device_id} eq $id }
               @{ $devices->{devices}};

            assert_ok( $result, "device $id" );

            assert_json_keys(
               $result,
               qw( device_id user_id display_name ),
            );
            assert_eq( $result->{user_id}, $user->user_id, "user_id" );
            assert_eq( $result->{display_name}, $DEVICES{$id}, "display_name" );
         }
         Future->done( 1 );
      });
   };

test "PUT /device/{deviceId} updates device fields",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      # easiest way to register a device is to /login with it
      my $DEVICE_ID = "login_device";

      matrix_login_again_with_user(
         $user,
         device_id => $DEVICE_ID,
         initial_device_display_name => "device display",
      )->then( sub {
         do_request_json_for(
            $user,
            method => "PUT",
            uri    => "/unstable/devices/${DEVICE_ID}",
            content => {
               display_name => "new display name",
            },
         );
      })->then( sub {
         matrix_get_device( $user, $DEVICE_ID );
      })->then( sub {
         my ( $device ) = @_;
         assert_json_keys(
            $device,
            qw( device_id user_id display_name ),
         );
         assert_eq( $device->{device_id}, $DEVICE_ID );
         assert_eq( $device->{display_name}, "new display name" );
         Future->done( 1 );
      });
   };

test "PUT /device/{deviceId} gives a 404 for unknown devices",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for(
         $user,
         method => "PUT",
         uri    => "/unstable/devices/unknown_device",
         content => {
            display_name => "new display name",
         },
      )->main::expect_http_404;
   };

test "DELETE /device/{deviceId}",
   requires => [ local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my $DEVICE_ID = "login_device";
      my $other_login;

      matrix_login_again_with_user(
         $user,
         device_id => $DEVICE_ID,
         initial_device_display_name => "device display",
      )->then( sub {
         ( $other_login ) = @_;

         # check that the access token we got works
         do_request_json_for(
            $other_login,
            method  => "GET",
            uri     => "/r0/sync",
         );
      })->then( sub {
         # delete the device
         do_request_json_for(
            $user,
            method => "DELETE",
            uri    => "/unstable/devices/${DEVICE_ID}",
         );
      })->then( sub {
         # the device should be deleted
         matrix_get_device( $user, $DEVICE_ID )
            ->main::expect_http_404;
      })->then( sub {
         my $delay = 0.1;
         # our access token should be invalidated
         try_repeat_until_success {
            do_request_json_for(
               $other_login,
               method  => "GET",
               uri     => "/r0/sync",
            )->main::expect_http_401
            ->else_with_f( sub {
               my ( $f ) = @_; delay( $delay *= 1.5 )->then( sub { $f } );
            })
         };
      })->then( sub {
         # so should our refresh token
         $user->http->do_request_json(
            method => "POST",
            uri    => "/r0/tokenrefresh",
            content => {
               refresh_token => $other_login->refresh_token,
            },
        )->main::expect_http_403;
      });
   };
