test "Can upload device keys",
   requires => [qw( register_new_user first_api_client )],

   provides => [qw( e2e_user_alice e2e_can_upload_keys )],

   do => sub {
      my ( $register_new_user, $http ) = @_;

      my $e2e_alice;
      # Register a user
      $register_new_user->( $http, "50-e2e-alice" )->then( sub {
         ( $e2e_alice ) = @_;

         provide e2e_user_alice => $e2e_alice;

         do_request_json_for( $e2e_alice,
            method  => "POST",
            uri     => "/v2_alpha/keys/upload/alices_first_device",
            content => {
               device_keys => {
                  user_id => "\@50-e2e-alice:localhost:8480",
                  device_id => "alices_first_device",
               },
               one_time_keys => {
                  "my_algorithm:my_id_1", "my+base64+key"
               }
            }
         )
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         require_json_keys( $content, "one_time_key_counts" );

         require_json_keys( $content->{one_time_key_counts}, "my_algorithm" );

         $content->{one_time_key_counts}{my_algorithm} eq "1" or
            die "Expected 1 one time key";

         provide e2e_can_upload_keys => 1;

         Future->done(1)
      })
   };
