multi_test "Can query remote device keys using POST",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user, $remote_user ) = @_;

      matrix_put_e2e_keys( $user, "alices_first_device" )
         ->SyTest::pass_on_done( "Uploaded key" )
      ->then( sub {
         do_request_json_for( $remote_user,
            method  => "POST",
            uri     => "/v2_alpha/keys/query/",
            content => {
               device_keys => {
                  $user->user_id => {}
               }
            }
         )
      })->then( sub {
         my ( $content ) = @_;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };
         assert_json_keys( $alice_keys, "alices_first_device" );
         # TODO: Check that the content matches what we uploaded.
         Future->done(1)
      });
   };
