multi_test "Can query remote device keys using POST",
   requires => [qw( first_api_client remote_users
                    can_upload_e2e_keys )],

   check => sub {
      my ( $first_api_client, $remote_users ) = @_;

      my $user;

      matrix_register_user( $first_api_client )
      ->then( sub {
         ( $user ) = @_;

         matrix_put_e2e_keys( $user, "alices_first_device" )
            ->SyTest::pass_on_done( "Uploaded key" )
      })->then( sub {
         do_request_json_for( $remote_users->[0],
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

         require_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         require_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };
         require_json_keys( $alice_keys, "alices_first_device" );
         # TODO: Check that the content matches what we uploaded.
         Future->done(1)
      });
   };
