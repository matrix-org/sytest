test "Can query remote device keys using POST",
   requires => [qw(
      remote_users e2e_user_alice do_request_json_for e2e_can_upload_keys
   )],

   check => sub {
      my ( $remote_users, $e2e_user_alice, $do_request_json_for ) = @_;

      $do_request_json_for->( $remote_users->[0],
         method  => "POST",
         uri     => "/v2_alpha/keys/query/",
         content => {
            device_keys => {
               $e2e_user_alice->user_id => {}
            }
         }
      )->then( sub {
         my ( $content ) = @_;

         require_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         require_json_keys( $device_keys, $e2e_user_alice->user_id );

         my $alice_keys = $device_keys->{ $e2e_user_alice->user_id };
         require_json_keys( $alice_keys, "alices_first_device" );
         # TODO: Check that the content matches what we uploaded.
         Future->done(1)
      });
   };
