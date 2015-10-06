my $preparer = local_user_preparer();

test "Can upload device keys",
   requires => [ $preparer ],

   provides => [qw( can_upload_e2e_keys )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/v2_alpha/keys/upload/alices_first_device",
         content => {
            device_keys => {
               user_id => $user->user_id,
               device_id => "alices_first_device",
            },
            one_time_keys => {
               "my_algorithm:my_id_1", "my+base64+key"
            }
         }
      )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         require_json_keys( $content, "one_time_key_counts" );

         require_json_keys( $content->{one_time_key_counts}, "my_algorithm" );

         $content->{one_time_key_counts}{my_algorithm} eq "1" or
            die "Expected 1 one time key";

         provide can_upload_e2e_keys => 1;

         Future->done(1)
      })
   };

test "Can query device keys using POST",
   requires => [ $preparer,
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/v2_alpha/keys/query/",
         content => {
            device_keys => {
               $user->user_id => {}
            }
         }
      )->then( sub {
         my ( $content ) = @_;

         require_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         require_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };
         require_json_keys( $alice_keys, "alices_first_device" );
         # TODO: Check that the content matches what we uploaded.
         Future->done(1)
      })
   };

test "Can query specific device keys using POST",
   requires => [ $preparer,
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/v2_alpha/keys/query/",
         content => {
            device_keys => {
               $user->user_id => [ "alices_first_device" ]
            }
         }
      )->then( sub {
         my ( $content ) = @_;

         require_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         require_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };
         require_json_keys( $alice_keys, "alices_first_device" );
         # TODO: Check that the content matches what we uploaded.
         Future->done(1)
      })
   };

test "Can query device keys using GET",
   requires => [ $preparer,
                 qw( can_upload_e2e_keys )],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/v2_alpha/keys/query/${\$user->user_id}"
      )->then( sub {
         my ( $content ) = @_;

         require_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         require_json_keys( $device_keys, $user->user_id );

         my $alice_keys = $device_keys->{ $user->user_id };
         require_json_keys( $alice_keys, "alices_first_device" );
         # TODO: Check that the content matches what we uploaded.
         Future->done(1)
      })
   };

push our @EXPORT, qw( matrix_put_e2e_keys );

sub matrix_put_e2e_keys
{
   # TODO(paul): I don't really know what's parametric about this
   my ( $user, $device_id ) = @_;

   do_request_json_for( $user,
      method => "POST",
      uri    => "/v2_alpha/keys/upload/$device_id",

      content => {
         device_keys => {
            user_id => $user->user_id,
            device_id => $device_id,
         },
         one_time_keys => {
            "my_algorithm:my_id_1" => "my+base64+key",
         }
      }
   )->then_done(1);
}
