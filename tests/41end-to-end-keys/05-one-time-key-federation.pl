multi_test "Can claim remote one time key using POST",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user, $remote_user ) = @_;

      my $device_id = $user->device_id;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/r0/keys/upload",
         content => {
            one_time_keys => {
               "test_algorithm:test_id", "kUuAFk05Ig0RjwDimSYHOXKro8BRB14G0efxVOq73VU"
            }
         }
      )->SyTest::pass_on_done( "Uploaded one-time keys" )
      ->then( sub {
         do_request_json_for( $remote_user,
            method  => "POST",
            uri     => "/r0/keys/claim",
            content => {
               one_time_keys => {
                  $user->user_id => {
                     $device_id => "test_algorithm"
                  }
               }
            }
         )
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "POST response", $content;

         assert_json_keys( $content, "one_time_keys" );

         my $one_time_keys = $content->{one_time_keys};
         assert_json_keys( $one_time_keys, $user->user_id );

         my $alice_keys = $one_time_keys->{ $user->user_id };
         assert_json_keys( $alice_keys, $device_id );

         my $alice_device_keys = $alice_keys->{$device_id};
         assert_json_keys( $alice_device_keys, "test_algorithm:test_id" );

         "kUuAFk05Ig0RjwDimSYHOXKro8BRB14G0efxVOq73VU" eq $alice_device_keys->{"test_algorithm:test_id"} or
            die "Unexpected key base64";

         pass "Took one time key";

         # a second claim should give no keys
         do_request_json_for( $remote_user,
            method  => "POST",
            uri     => "/r0/keys/claim",
            content => {
               one_time_keys => {
                  $user->user_id => {
                     $device_id => "test_algorithm"
                  }
               }
            }
         )
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Second claim response", $content;

         assert_json_keys( $content, "one_time_keys" );
         assert_deeply_eq( $content->{one_time_keys}, {}, "Second claim result" );

         Future->done(1)
      });
   };
