our @EXPORT = qw( matrix_get_device );

sub matrix_get_device {
   my ($user, $device_id) = @_;

   return do_request_json_for(
      $user,
      method => "GET",
      uri => "/unstable/devices/${device_id}",
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
         assert_json_list($devices->{devices});

         # check each of the devices we logged in with is returned
         for my $id ( keys( %DEVICES )) {
            my $matched = 0;
            RESULT: foreach my $result ( @{ $devices->{devices}} ) {
               if ( $result->{device_id} ne $id ) {
                  next RESULT;
               }

               $matched = 1;
               assert_json_keys(
                  $result,
                  qw( device_id user_id display_name ),
               );
               assert_eq( $result->{user_id}, $user->user_id, "user_id" );
               assert_eq( $result->{display_name}, $DEVICES{$id}, "display_name" );
               last RESULT;
            }
            assert_ok( $matched, "device $id" );
         }
         Future->done( 1 );
      });
   };
