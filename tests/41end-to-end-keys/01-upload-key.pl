my $fixture = local_user_fixture();

test "Can upload device keys",
   requires => [ $fixture ],

   proves => [qw( can_upload_e2e_keys )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/r0/keys/upload",
         content => {
            device_keys => {
               user_id => $user->user_id,
               device_id => $user->device_id,
            },
            one_time_keys => {
               "my_algorithm:my_id_1", "my+base64+key"
            }
         }
      )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, "one_time_key_counts" );

         assert_json_keys( $content->{one_time_key_counts}, "my_algorithm" );

         $content->{one_time_key_counts}{my_algorithm} eq "1" or
            die "Expected 1 one time key";

         Future->done(1)
      })
  };

test "Should reject keys claiming to belong to a different user",
   requires => [ $fixture ],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for(
         $user,
         method  => "POST",
         uri     => "/r0/keys/upload",
         content => {
            device_keys => {
               user_id => "\@50-e2e-alice:localhost:8480",
               device_id => "alices_first_device",
            },
         }
      )->main::expect_http_4xx;
   };

test "Can query device keys using POST",
   requires => [ $fixture,
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user ) = @_;

      matrix_get_e2e_keys(
         $user, $user->user_id
      )->then( sub {
         my ( $content ) = @_;

         log_if_fail( "/query response", $content );

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };
         assert_json_keys( $alice_keys, $user->device_id );

         my $alice_device_keys = $alice_keys->{ $user->device_id };
         assert_json_keys( $alice_device_keys, "unsigned" );

         my $unsigned = $alice_device_keys->{unsigned};

         # display_name should not be present by default
         exists $unsigned->{device_display_name} and
           die "Expected to get no device_display_name";

         # TODO: Check that the content matches what we uploaded.

         Future->done(1)
      })
   };

test "Can query specific device keys using POST",
   requires => [ $fixture,
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user ) = @_;

      my $device_id = $user->device_id;

      matrix_get_e2e_keys(
         $user, $user->user_id, [ $device_id ]
      )->then( sub {
         my ( $content ) = @_;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };
         assert_json_keys( $alice_keys, $device_id );
         # TODO: Check that the content matches what we uploaded.
         Future->done(1)
      })
   };

test "query for user with no keys returns empty key dict",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_get_e2e_keys(
         $user, $user->user_id
      )->then( sub {
         my ( $content ) = @_;

         log_if_fail( "/query response", $content );

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };

         assert_json_object( $alice_keys );
         assert_ok( !%{$alice_keys}, "unexpected keys" );

         Future->done(1)
      })
   };

push our @EXPORT, qw( matrix_put_e2e_keys matrix_get_e2e_keys );

sub matrix_put_e2e_keys
{
   # TODO(paul): I don't really know what's parametric about this
   my ( $user, %params ) = @_;

   my $dk = $params{device_keys} // {};
   my %device_keys = %$dk;
   $device_keys{user_id} = $user->user_id;
   $device_keys{device_id} = $user->device_id;

   do_request_json_for( $user,
      method => "POST",
      uri    => "/r0/keys/upload",

      content => {
         device_keys => \%device_keys,
         one_time_keys => {
            "my_algorithm:my_id_1" => "my+base64+key",
         }
      }
   );
}

=head2 matrix_get_e2e_keys

   matrix_get_e2e_keys( $user, $keys, $devices )

Get a user's keys, optionally specifying the devices

=cut

sub matrix_get_e2e_keys {
   my ( $from_user, $target_user_id, $devices ) = @_;

   do_request_json_for( $from_user,
       method  => "POST",
       uri     => "/r0/keys/query",
       content => {
          device_keys => {
             $target_user_id => $devices // []
          }
       }
   );
}
