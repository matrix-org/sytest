multi_test "Can claim remote one time key using POST",
   requires => [qw(
      remote_users e2e_user_alice e2e_can_upload_keys
   )],

   check => sub {
      my ( $remote_users, $e2e_user_alice ) = @_;

      do_request_json_for( $e2e_user_alice,
         method  => "POST",
         uri     => "/v2_alpha/keys/upload/alices_first_device",
         content => {
            one_time_keys => {
               "test_algorithm:test_id", "test+base64+key"
            }
         }
      )->SyTest::pass_on_done( "Uploaded one-time keys" )
      ->then( sub {
         do_request_json_for( $e2e_user_alice,
            method => "GET",
            uri    => "/v2_alpha/keys/upload/alices_first_device"
         )
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "First device content", $content;

         require_json_keys( $content, "one_time_key_counts" );
         require_json_keys( $content->{one_time_key_counts}, "test_algorithm" );

         $content->{one_time_key_counts}{test_algorithm} eq "1" or
            die "Expected 1 one time key";

         pass "Counted one time keys";

         do_request_json_for( $remote_users->[0],
            method  => "POST",
            uri     => "/v2_alpha/keys/claim",
            content => {
               one_time_keys => {
                  $e2e_user_alice->user_id => {
                     alices_first_device => "test_algorithm"
                  }
               }
            }
         )
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "POST response", $content;

         require_json_keys( $content, "one_time_keys" );

         my $one_time_keys = $content->{one_time_keys};
         require_json_keys( $one_time_keys, $e2e_user_alice->user_id );

         my $alice_keys = $one_time_keys->{ $e2e_user_alice->user_id };
         require_json_keys( $alice_keys, "alices_first_device" );

         my $alice_device_keys = $alice_keys->{alices_first_device};
         require_json_keys( $alice_device_keys, "test_algorithm:test_id" );

         "test+base64+key" eq $alice_device_keys->{"test_algorithm:test_id"} or
            die "Unexpected key base64";

         pass "Took one time key";

         do_request_json_for( $e2e_user_alice,
            method => "GET",
            uri    => "/v2_alpha/keys/upload/alices_first_device"
         )
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "First device content", $content;

         require_json_keys( $content, "one_time_key_counts" );

         exists $content->{one_time_key_counts}{test_algorithm} and
            die "Expected that the key would be removed from the counts";

         Future->done(1)
      });
   };
