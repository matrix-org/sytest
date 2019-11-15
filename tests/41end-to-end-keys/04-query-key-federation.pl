multi_test "Can query remote device keys using POST",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user, $remote_user ) = @_;

      matrix_put_e2e_keys( $user )
         ->SyTest::pass_on_done( "Uploaded key" )
      ->then( sub {
         matrix_set_device_display_name( $user, $user->device_id, "test display name" ),
      })->then( sub {
         matrix_get_e2e_keys(
            $remote_user, $user->user_id
         )
      })->then( sub {
         my ( $content ) = @_;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };
         assert_json_keys( $alice_keys, $user->device_id );

         my $alice_device_keys = $alice_keys->{ $user->device_id };

         # TODO: Check that the content matches what we uploaded.

         assert_eq( $alice_device_keys->{"unsigned"}->{"device_display_name"},
                    "test display name" );

         Future->done(1)
      });
   };
