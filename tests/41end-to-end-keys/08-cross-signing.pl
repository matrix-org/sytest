use Crypt::NaCl::Sodium;
use MIME::Base64;
use Protocol::Matrix qw( sign_json );

my $crypto_sign = Crypt::NaCl::Sodium->sign;

test "Can upload self-signing keys",
   requires => [ local_user_fixture() ],

   proves => [qw( can_upload_self_signing_keys )],

   do => sub {
      my ( $user ) = @_;
      my $user_id = $user->user_id;

      matrix_set_cross_signing_key( $user, {
          "auth" => {
              "type"     => "m.login.password",
              "user"     => $user_id,
              "password" => $user->password,
          },
          "self_signing_key" => {
              # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
              "user_id" => $user_id,
              "usage" => ["self_signing"],
              "keys" => {
                  "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                      => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
              },
          },
      })->then( sub {
         matrix_set_cross_signing_key( $user, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user_id,
                 "password" => $user->password,
             },
             "self_signing_key" => {
                 # private key: 4TL4AjRYwDVwD3pqQzcor+ez/euOB1/q78aTJ+czDNs
                 "user_id" => $user_id,
                 "usage" => ["self_signing"],
                 "keys" => {
                     "ed25519:Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw"
                         => "Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw",
                 },
                 "replaces" => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
             },
         });
      })->then( sub {
         matrix_get_keys( $user, $user_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "self_signing_keys" );
         assert_json_keys( $content->{self_signing_keys}, $user_id );
         assert_deeply_eq( $content->{self_signing_keys}->{$user_id}, {
               "user_id" => $user_id,
               "usage" => ["self_signing"],
               "keys" => {
                   "ed25519:Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw"
                       => "Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw",
               },
               "replaces" => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
            },
         );

         Future->done( 1 );
      });
   };

test "Fails to upload self-signing keys in invalid conditions",
   requires => [ local_user_fixture() ],

   do => sub {
      my ( $user ) = @_;
      my $user_id = $user->user_id;

      # uploading key requires auth
      matrix_set_cross_signing_key( $user, {
          "self_signing_key" => {
              # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
              "user_id" => $user_id,
              "usage" => ["self_signing"],
              "keys" => {
                  "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                      => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
              },
          },
      })->main::expect_http_401->then( sub {
         # set a valid key, to test failures in replacing a key
         matrix_set_cross_signing_key( $user, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user_id,
                 "password" => $user->password,
             },
             "self_signing_key" => {
                 # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
                 "user_id" => $user_id,
                 "usage" => ["self_signing"],
                 "keys" => {
                     "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                         => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
                 },
             },
         });
      })->then( sub {
         # missing "replaces" property
         matrix_set_cross_signing_key( $user, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user_id,
                 "password" => $user->password,
             },
             "self_signing_key" => {
                 # private key: 4TL4AjRYwDVwD3pqQzcor+ez/euOB1/q78aTJ+czDNs
                 "user_id" => $user_id,
                 "usage" => ["self_signing"],
                 "keys" => {
                     "ed25519:Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw"
                         => "Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw",
                 },
             },
         });
      })->main::expect_http_400->then( sub {
         Future->done( 1 );
      });
   };

test "local self-signing notifies users",
   requires => [ local_user_fixtures( 2 ) ],

   proves => [qw( can_upload_self_signing_keys )],

   do => sub {
      # when a user uploads a self-signing key or uploads a new signature,
      # everyone who shares a room with them should be notified
      my ( $user1, $user2 ) = @_;
      my $user_id = $user1->user_id;
      my $device_id = $user1->device_id;

      my ( $self_signing_pubkey, $self_signing_secret_key ) = $crypto_sign->keypair( decode_base64( "2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0" ) );
      my $cross_signature;

      matrix_sync( $user1 )->then(sub {
         matrix_sync( $user2 );
      })->then( sub {
         matrix_create_room( $user1 );
      })->then( sub {
         my ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_set_cross_signing_key( $user1, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user_id,
                 "password" => $user1->password,
             },
             "self_signing_key" => {
                 # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
                 "user_id" => $user_id,
                 "usage" => ["self_signing"],
                 "keys" => {
                     "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                         => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
                 },
             },
         });
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user1 );
      })->then( sub {
         sync_until_user_in_device_list( $user2, $user1 );
      })->then( sub {
         matrix_upload_device_keys( $user1, {
             "user_id" => $user_id,
             "device_id" => $device_id,
             "algorithms" => ["m.olm.curve25519-aes-sha256", "m.megolm.v1.aes-sha"],
             "keys" => {
                 "curve25519:".$device_id => "curve25519+key",
                 "ed25519:".$device_id => "ed25519+key",
             },
             "signatures" => {
                 $user_id => {
                     "ed25519:".$device_id => "self+signature",
                 },
             },
         } );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user1 );
      })->then( sub {
         sync_until_user_in_device_list( $user2, $user1 );
      })->then( sub {
         my $cross_signed_device = {
             "user_id" => $user_id,
             "device_id" => $device_id,
             "algorithms" => ["m.olm.curve25519-aes-sha256", "m.megolm.v1.aes-sha"],
             "keys" => {
                 "curve25519:".$device_id => "curve25519+key",
                 "ed25519:".$device_id => "ed25519+key",
             }
         };
         sign_json(
            $cross_signed_device, secret_key => $self_signing_secret_key,
            origin => $user_id, key_id => "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
         );
         log_if_fail "sent signature", $cross_signed_device;
         $cross_signature = $cross_signed_device->{signatures}->{$user_id}->{"ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"};
         matrix_upload_signatures( $user1, {
             $user_id => {
                 $device_id => $cross_signed_device
             }
         } );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user1 );
      })->then( sub {
         sync_until_user_in_device_list( $user2, $user1 );
      })->then( sub {
         matrix_get_keys( $user1, $user_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "device_keys" );
         assert_json_keys( $content->{device_keys}, $user_id );
         assert_json_keys( $content->{device_keys}->{$user_id}, $device_id);
         assert_json_keys( $content->{device_keys}->{$user_id}->{$device_id}
                           ->{signatures}->{$user_id},
                           "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" );
         assert_deeply_eq( $content->{device_keys}->{$user_id}->{$device_id}
                           ->{signatures}->{$user_id}, {
            "ed25519:".$device_id => "self+signature",
            "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" => $cross_signature,
         } );

         matrix_get_keys( $user2, $user_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "device_keys" );
         assert_json_keys( $content->{device_keys}, $user_id );
         assert_json_keys( $content->{device_keys}->{$user_id}, $device_id);
         assert_json_keys( $content->{device_keys}->{$user_id}->{$device_id}
                           ->{signatures}->{$user_id},
                           "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" );
         assert_deeply_eq( $content->{device_keys}->{$user_id}->{$device_id}
                           ->{signatures}->{$user_id}, {
            "ed25519:".$device_id => "self+signature",
            "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk" => $cross_signature,
         } );

         Future->done( 1 );
      });
   };

test "local user-signing notifies users",
   requires => [ local_user_fixtures( 2 ) ],

   proves => [qw( can_upload_self_signing_keys )],

   do => sub {
      # when a user uploads a user-signing key or uploads a new signature,
      # they should be notified
      my ( $user1, $user2 ) = @_;
      my $user_id = $user1->user_id;
      my $device_id = $user1->device_id;
      my $user2_id = $user2->user_id;

      my ( $self_signing_pubkey, $self_signing_secret_key ) = $crypto_sign->keypair( decode_base64( "2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0" ) );
      my ( $user_signing_pubkey, $user_signing_secret_key ) = $crypto_sign->keypair( decode_base64( "4TL4AjRYwDVwD3pqQzcor+ez/euOB1/q78aTJ+czDNs" ) );
      my $cross_signature;

      matrix_sync( $user1 )->then(sub {
         matrix_sync( $user2 );
      })->then( sub {
         matrix_create_room( $user1 );
      })->then( sub {
         my ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         my $user_signing_key = {
             # private key: 4TL4AjRYwDVwD3pqQzcor+ez/euOB1/q78aTJ+czDNs
            "user_id" => $user_id,
            "usage" => ["user_signing"],
            "keys" => {
                "ed25519:Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw"
                    => "Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw",
            }
         };
         sign_json(
            $user_signing_key, secret_key => $self_signing_secret_key,
            origin => $user_id, key_id => "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
         );
         matrix_set_cross_signing_key( $user1, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user_id,
                 "password" => $user1->password,
             },
             "self_signing_key" => {
                 # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
                 "user_id" => $user_id,
                 "usage" => ["self_signing"],
                 "keys" => {
                     "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                         => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
                 },
             },
             "user_signing_key" => $user_signing_key
         });
      })->then( sub {
         matrix_set_cross_signing_key( $user2, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user2_id,
                 "password" => $user2->password,
             },
             "self_signing_key" => {
                 # private key: OMkooTr76ega06xNvXIGPbgvvxAOzmQncN8VObS7aBA
                 "user_id" => $user2_id,
                 "usage" => ["self_signing"],
                 "keys" => {
                     "ed25519:NnHhnqiMFQkq969szYkooLaBAXW244ZOxgukCvm2ZeY"
                         => "NnHhnqiMFQkq969szYkooLaBAXW244ZOxgukCvm2ZeY",
                 },
             },
         });
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         sync_until_user_in_device_list( $user2, $user2 );
      })->then( sub {
         my $cross_signed_device = {
             "user_id" => $user2_id,
             "usage" => ["self_signing"],
             "keys" => {
                 "ed25519:NnHhnqiMFQkq969szYkooLaBAXW244ZOxgukCvm2ZeY"
                     => "NnHhnqiMFQkq969szYkooLaBAXW244ZOxgukCvm2ZeY",
             },
         };
         sign_json(
            $cross_signed_device, secret_key => $user_signing_secret_key,
            origin => $user_id, key_id => "ed25519:Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw"
         );
         log_if_fail "sent signature", $cross_signed_device;
         $cross_signature = $cross_signed_device->{signatures}->{$user_id}->{"ed25519:Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw"};
         matrix_upload_signatures( $user1, {
             $user2_id => {
                 "NnHhnqiMFQkq969szYkooLaBAXW244ZOxgukCvm2ZeY" => $cross_signed_device
             }
         } );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         matrix_get_keys( $user1, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "self_signing_keys" );
         assert_json_keys( $content->{self_signing_keys}, $user2_id );
         assert_json_keys( $content->{self_signing_keys}->{$user2_id}, "signatures");
         assert_json_keys( $content->{self_signing_keys}->{$user2_id}
                           ->{signatures}, $user_id );
         assert_deeply_eq( $content->{self_signing_keys}->{$user2_id}
                           ->{signatures}->{$user_id}, {
             "ed25519:Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw"
                 => $cross_signature,
         } );

         matrix_get_keys( $user2, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "self_signing_keys" );
         assert_json_keys( $content->{self_signing_keys}, $user2_id );
         exists $content->{self_signing_keys}->{$user2_id}->{signatures}
             && exists $content->{self_signing_keys}->{$user2_id}->{signatures}->{$user_id}
             and croak "Expected signature to not be present";

         Future->done( 1 );
      });
   };

=head2 matrix_set_cross_signing_key

   matrix_set_cross_signing_key( $user, $keys )

Set cross-signing keys

=cut

sub matrix_set_cross_signing_key {
   my ( $user, $keys ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/unstable/keys/device_signing/upload",
      content => $keys,
   );
}

=head2 matrix_get_keys

   matrix_get_keys( $user, $keys )

Get a user's keys

=cut

sub matrix_get_keys {
   my ( $from_user, $target_user_id ) = @_;

   do_request_json_for( $from_user,
       method  => "POST",
       uri     => "/unstable/keys/query",
       content => {
          device_keys => {
             $target_user_id => {}
          }
       }
   );
}

=head2 matrix_upload_device_key

   matrix_upload_device_key( $user, $keys )

upload a device key

=cut

sub matrix_upload_device_keys {
   my ( $user, $keys ) = @_;

   do_request_json_for(
      $user,
      method  => "POST",
      uri     => "/unstable/keys/upload",
      content => {
         device_keys => $keys,
      }
   );
}

=head2 matrix_upload_signatures

   matrix_upload_signatures( $user, $signatures )

upload a device key

=cut

sub matrix_upload_signatures {
   my ( $user, $signatures ) = @_;

   do_request_json_for(
      $user,
      method  => "POST",
      uri     => "/unstable/keys/signatures/upload",
      content => $signatures,
   );
}

