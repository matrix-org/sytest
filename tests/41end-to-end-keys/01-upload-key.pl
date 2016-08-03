my $fixture = local_user_fixture();

test "Can upload device keys",
   requires => [ $fixture ],

   proves => [qw( can_upload_e2e_keys )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/unstable/keys/upload",
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

test "Can query device keys using POST",
   requires => [ $fixture,
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/unstable/keys/query/",
         content => {
            device_keys => {
               $user->user_id => {}
            }
         }
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

         # display_name should be null by default
         exists $unsigned->{device_display_name} or
           die "Expected to get a (null) device_display_name";
         defined $unsigned->{device_display_name} and
           die "Device display name was unexpectedly defined.";

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

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/unstable/keys/query/",
         content => {
            device_keys => {
               $user->user_id => [ $device_id ]
            }
         }
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

test "Can query device keys using GET",
   requires => [ $fixture,
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/unstable/keys/query/${\$user->user_id}"
      )->then( sub {
         my ( $content ) = @_;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };
         assert_json_keys( $alice_keys, $user->device_id );
         # TODO: Check that the content matches what we uploaded.
         Future->done(1)
      })
   };

push our @EXPORT, qw( matrix_put_e2e_keys );

sub matrix_put_e2e_keys
{
   # TODO(paul): I don't really know what's parametric about this
   my ( $user ) = @_;

   do_request_json_for( $user,
      method => "POST",
      uri    => "/unstable/keys/upload",

      content => {
         device_keys => {
            user_id => $user->user_id,
            device_id => $user->device_id,
         },
         one_time_keys => {
            "my_algorithm:my_id_1" => "my+base64+key",
         }
      }
   )->then_done(1);
}
