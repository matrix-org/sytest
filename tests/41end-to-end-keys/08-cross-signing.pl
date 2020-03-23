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
          "master_key" => {
              # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
              "user_id" => $user_id,
              "usage" => ["master"],
              "keys" => {
                  "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                      => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
              },
          },
      })->then( sub {
         matrix_get_e2e_keys( $user, $user_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "master_keys" );
         assert_json_keys( $content->{master_keys}, $user_id );
         assert_deeply_eq( $content->{master_keys}->{$user_id}, {
               "user_id" => $user_id,
               "usage" => ["master"],
               "keys" => {
                  "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                      => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
               },
            },
         );

         Future->done( 1 );
      });
   };

test "Fails to upload self-signing keys with no auth",
   requires => [ local_user_fixture(), qw( can_upload_self_signing_keys ) ],

   do => sub {
      my ( $user ) = @_;
      my $user_id = $user->user_id;

      matrix_set_cross_signing_key( $user, {
          "master_key" => {
              # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
              "user_id" => $user_id,
              "usage" => ["master"],
              "keys" => {
                  "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                      => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
              },
          },
      })->main::expect_http_401;
   };

test "Fails to upload self-signing key without master key",
   requires => [ local_user_fixture(), qw( can_upload_self_signing_keys ) ],

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
      })->main::expect_http_400;
   };

test "Changing master key notifies local users",
   requires => [ local_user_fixtures( 2 ), qw( can_upload_self_signing_keys ) ],

   do => sub {
      # when a user uploads a self-signing key or uploads a new signature,
      # everyone who shares a room with them should be notified
      my ( $user1, $user2 ) = @_;
      my $user_id = $user1->user_id;
      my $device_id = $user1->device_id;

      my ( $master_pubkey, $master_secret_key ) = $crypto_sign->keypair( decode_base64( "2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0" ) );
      my ( $self_signing_pubkey, $self_signing_secret_key ) = $crypto_sign->keypair( decode_base64( "HvQBbU+hc2Zr+JP1sE0XwBe1pfZZEYtJNPJLZJtS+F8" ) );
      my $cross_signature;

      matrix_sync( $user1 )->then(sub {
         matrix_sync( $user2 );
      })->then( sub {
         matrix_create_room( $user1 );
      })->then( sub {
         my ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         my $self_signing_key = {
            # private key: HvQBbU+hc2Zr+JP1sE0XwBe1pfZZEYtJNPJLZJtS+F8
            "user_id" => $user_id,
                "usage" => ["self_signing"],
                "keys" => {
                   "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ"
                       => "EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ",
            },
         };
         sign_json(
            $self_signing_key, secret_key => $master_secret_key,
            origin => $user_id, key_id => "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
         );
         matrix_set_cross_signing_key( $user1, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user_id,
                 "password" => $user1->password,
             },
             "master_key" => {
                 # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
                 "user_id" => $user_id,
                 "usage" => ["master"],
                 "keys" => {
                     "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                         => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
                 },
             },
             "self_signing_key" => $self_signing_key,
         });
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user1 );
      })->then( sub {
         sync_until_user_in_device_list( $user2, $user1 );
      })->then( sub {
         matrix_put_e2e_keys( $user1, device_keys => {
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
         my ( $content ) = @_;

         log_if_fail "signature upload failures", $content;

         if (exists $content->{failures}) {
            # either failures should not exist, or should be empty
            assert_deeply_eq( $content->{failures}, {} );
         }

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
            origin => $user_id, key_id => "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ"
         );
         log_if_fail "sent signature", $cross_signed_device;
         $cross_signature = $cross_signed_device->{signatures}->{$user_id}->{"ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ"};
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
         matrix_get_e2e_keys( $user1, $user_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "device_keys" );
         assert_json_keys( $content->{device_keys}, $user_id );
         assert_json_keys( $content->{device_keys}->{$user_id}, $device_id);
         assert_json_keys( $content->{device_keys}->{$user_id}->{$device_id}
                           ->{signatures}->{$user_id},
                           "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ" );
         assert_deeply_eq( $content->{device_keys}->{$user_id}->{$device_id}
                           ->{signatures}->{$user_id}, {
            "ed25519:".$device_id => "self+signature",
            "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ" => $cross_signature,
         } );

         matrix_get_e2e_keys( $user2, $user_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "device_keys" );
         assert_json_keys( $content->{device_keys}, $user_id );
         assert_json_keys( $content->{device_keys}->{$user_id}, $device_id);
         assert_json_keys( $content->{device_keys}->{$user_id}->{$device_id}
                           ->{signatures}->{$user_id},
                           "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ" );
         assert_deeply_eq( $content->{device_keys}->{$user_id}->{$device_id}
                           ->{signatures}->{$user_id}, {
            "ed25519:".$device_id => "self+signature",
            "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ" => $cross_signature,
         } );

         Future->done( 1 );
      });
   };

test "Changing user-signing key notifies local users",
   requires => [ local_user_fixtures( 2 ), qw( can_upload_self_signing_keys ) ],

   do => sub {
      # when a user uploads a user-signing key or uploads a new signature,
      # they should be notified
      my ( $user1, $user2 ) = @_;
      my $user_id = $user1->user_id;
      my $device_id = $user1->device_id;
      my $user2_id = $user2->user_id;

      my ( $master_pubkey, $master_secret_key ) = $crypto_sign->keypair( decode_base64( "2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0" ) );
      my ( $self_signing_pubkey, $self_signing_secret_key ) = $crypto_sign->keypair( decode_base64( "HvQBbU+hc2Zr+JP1sE0XwBe1pfZZEYtJNPJLZJtS+F8" ) );
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
         my $self_signing_key = {
            # private key: HvQBbU+hc2Zr+JP1sE0XwBe1pfZZEYtJNPJLZJtS+F8
            "user_id" => $user_id,
                "usage" => ["self_signing"],
                "keys" => {
                   "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ"
                       => "EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ",
            },
         };
         sign_json(
            $self_signing_key, secret_key => $master_secret_key,
            origin => $user_id, key_id => "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
         );
         matrix_set_cross_signing_key( $user1, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user_id,
                 "password" => $user1->password,
             },
             "master_key" => {
                 # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
                 "user_id" => $user_id,
                 "usage" => ["master"],
                 "keys" => {
                     "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                         => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
                 },
             },
             "self_signing_key" => $self_signing_key
         });
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user1 );
      })->then( sub {
         sync_until_user_in_device_list( $user2, $user1 );
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
            $user_signing_key, secret_key => $master_secret_key,
            origin => $user_id, key_id => "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
         );
         matrix_set_cross_signing_key( $user1, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user_id,
                 "password" => $user1->password,
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
             "master_key" => {
                 # private key: OMkooTr76ega06xNvXIGPbgvvxAOzmQncN8VObS7aBA
                 "user_id" => $user2_id,
                 "usage" => ["master"],
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
         my ( $body ) = @_;

         log_if_fail $user2 . " sync body", $body;

         any { $_ eq $user1->user_id } @{ $body->{device_lists}{changed} }
            and die "user1 in changed list after uploading user-signing key";

         my $cross_signed_device = {
             "user_id" => $user2_id,
             "usage" => ["master"],
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
         matrix_get_e2e_keys( $user1, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "master_keys" );
         assert_json_keys( $content->{master_keys}, $user2_id );
         assert_json_keys( $content->{master_keys}->{$user2_id}, "signatures");
         assert_json_keys( $content->{master_keys}->{$user2_id}
                           ->{signatures}, $user_id );
         assert_deeply_eq( $content->{master_keys}->{$user2_id}
                           ->{signatures}->{$user_id}, {
             "ed25519:Hq6gL+utB4ET+UvD5ci0kgAwsX6qP/zvf8v6OInU5iw"
                 => $cross_signature,
         } );

         matrix_get_e2e_keys( $user2, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "master_keys" );
         assert_json_keys( $content->{master_keys}, $user2_id );
         exists $content->{master_keys}->{$user2_id}->{signatures}
             && exists $content->{master_keys}->{$user2_id}->{signatures}->{$user_id}
             and croak "Expected signature to not be present";

         Future->done( 1 );
      });
   };

test "can fetch self-signing keys over federation",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_self_signing_keys) ],

   do => sub {
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user1_device = $user1->device_id;
      my $user2_id = $user2->user_id;
      my $user2_device = $user2->device_id;

      my ( $master_pubkey, $master_secret_key ) = $crypto_sign->keypair( decode_base64( "2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0" ) );
      my $self_signing_key = {
         # private key: HvQBbU+hc2Zr+JP1sE0XwBe1pfZZEYtJNPJLZJtS+F8
         "user_id" => $user2_id,
         "usage" => ["self_signing"],
         "keys" => {
            "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ"
                => "EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ",
         },
      };
      sign_json(
         $self_signing_key, secret_key => $master_secret_key,
         origin => $user2_id, key_id => "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
          );

      matrix_set_cross_signing_key( $user2, {
          "auth" => {
              "type"     => "m.login.password",
              "user"     => $user2_id,
              "password" => $user2->password,
          },
          "master_key" => {
              # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
              "user_id" => $user2_id,
              "usage" => ["master"],
              "keys" => {
                  "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                      => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
              },
          },
          "self_signing_key" => $self_signing_key,
      })->then( sub {
         my ( $content ) = @_;

         matrix_get_e2e_keys( $user1, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "master_keys" );
         assert_json_keys( $content->{master_keys}, $user2_id );
         assert_deeply_eq( $content->{master_keys}->{$user2_id}, {
               "user_id" => $user2_id,
               "usage" => ["master"],
               "keys" => {
                  "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                      => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
               },
            },
         );
         assert_json_keys( $content, "self_signing_keys" );
         assert_json_keys( $content->{self_signing_keys}, $user2_id );
         assert_deeply_eq( $content->{self_signing_keys}->{$user2_id}, $self_signing_key);

         Future->done(1);
      });
};

test "uploading self-signing key notifies over federation",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_self_signing_keys) ],

   do => sub {
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user1_device = $user1->device_id;
      my $user2_id = $user2->user_id;
      my $user2_device = $user2->device_id;

      my $room_id;

      my ( $master_pubkey, $master_secret_key ) = $crypto_sign->keypair( decode_base64( "2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0" ) );
      my $self_signing_key = {
         # private key: HvQBbU+hc2Zr+JP1sE0XwBe1pfZZEYtJNPJLZJtS+F8
         "user_id" => $user2_id,
         "usage" => ["self_signing"],
         "keys" => {
            "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ"
                => "EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ",
         },
      };
      sign_json(
         $self_signing_key, secret_key => $master_secret_key,
         origin => $user2_id, key_id => "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
          );

      matrix_put_e2e_keys( $user2, device_keys => {
             "algorithms" => ["m.olm.curve25519-aes-sha256", "m.megolm.v1.aes-sha"],
             "keys" => {
                 "curve25519:".$user2_device => "curve25519+key",
                 "ed25519:".$user2_device => "ed25519+key",
             },
             "signatures" => {
                 $user2_id => {
                     "ed25519:".$user2_device => "self+signature",
                 },
             },
      } )->then( sub {
         matrix_create_room( $user1 );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_sync( $user1 );
      })->then( sub {
         matrix_invite_user_to_room( $user1, $user2, $room_id )
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         matrix_join_room( $user2, $room_id );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         matrix_set_cross_signing_key( $user2, {
             "auth" => {
                 "type"     => "m.login.password",
                  "user"     => $user2_id,
                  "password" => $user2->password,
             },
             "master_key" => {
                 # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
                 "user_id" => $user2_id,
                 "usage" => ["master"],
                 "keys" => {
                     "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                         => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
                 },
             },
             "self_signing_key" => $self_signing_key,
         });
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         matrix_get_e2e_keys( $user1, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content, "master_keys" );
         assert_json_keys( $content->{master_keys}, $user2_id );
         assert_deeply_eq( $content->{master_keys}->{$user2_id}, {
               "user_id" => $user2_id,
               "usage" => ["master"],
               "keys" => {
                  "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                      => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
               },
            },
         );
         assert_json_keys( $content, "self_signing_keys" );
         assert_json_keys( $content->{self_signing_keys}, $user2_id );
         assert_deeply_eq( $content->{self_signing_keys}->{$user2_id}, $self_signing_key);

         Future->done(1);
      });
   };

test "uploading signed devices gets propagated over federation",
   requires => [ local_user_fixture(), remote_user_fixture() ],

   do => sub {
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user1_device = $user1->device_id;
      my $user2_id = $user2->user_id;
      my $user2_device = $user2->device_id;

      my $room_id;

      my ( $master_pubkey, $master_secret_key ) = $crypto_sign->keypair( decode_base64( "2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0" ) );
      my ( $self_signing_pubkey, $self_signing_secret_key ) = $crypto_sign->keypair( decode_base64( "HvQBbU+hc2Zr+JP1sE0XwBe1pfZZEYtJNPJLZJtS+F8" ) );
      my $self_signing_key = {
         # private key: HvQBbU+hc2Zr+JP1sE0XwBe1pfZZEYtJNPJLZJtS+F8
         "user_id" => $user2_id,
         "usage" => ["self_signing"],
         "keys" => {
            "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ"
                => "EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ",
         },
      };
      sign_json(
         $self_signing_key,
         secret_key => $master_secret_key,
         origin => $user2_id,
         key_id => "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
      );

      my $device = {
          "user_id" => $user2_id,
          "device_id" => $user2_device,
          "algorithms" => ["m.olm.curve25519-aes-sha256", "m.megolm.v1.aes-sha"],
          "keys" => {
              "curve25519:$user2_device" => "curve25519+key",
              "ed25519:$user2_device" => "ed25519+key",
          }
      };
      my $cross_signature;

      matrix_put_e2e_keys( $user2, device_keys => $device)->then( sub {
         matrix_set_cross_signing_key( $user2, {
             "auth" => {
                 "type"     => "m.login.password",
                 "user"     => $user2_id,
                 "password" => $user2->password,
             },
             "master_key" => {
                 # private key: 2lonYOM6xYKdEsO+6KrC766xBcHnYnim1x/4LFGF8B0
                 "user_id" => $user2_id,
                 "usage" => ["master"],
                 "keys" => {
                     "ed25519:nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk"
                         => "nqOvzeuGWT/sRx3h7+MHoInYj3Uk2LD/unI9kDYcHwk",
                 },
             },
             "self_signing_key" => $self_signing_key,
          });
      })->then( sub {
         matrix_create_room( $user1 );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_sync( $user1 );
      })->then( sub {
         matrix_invite_user_to_room( $user1, $user2, $room_id )
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         matrix_join_room( $user2, $room_id );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         sign_json(
            $device, secret_key => $self_signing_secret_key,
            origin => $user2_id, key_id => "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ"
         );
         log_if_fail "sent signature", $device;
         $cross_signature = $device->{signatures}->{$user2_id}->{"ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ"};
         matrix_upload_signatures( $user2, {
             $user2_id => {
                 $user2_device => $device
             }
         } );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         matrix_get_e2e_keys( $user1, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "key query content", $content;

         assert_json_keys( $content->{device_keys}->{$user2_id}->{$user2_device}, "signatures" );

         assert_deeply_eq( $content->{device_keys}->{$user2_id}->{$user2_device}->{signatures}, {
            $user2_id => {
               "ed25519:EmkqvokUn8p+vQAGZitOk4PWjp7Ukp3txV2TbMPEiBQ" => $cross_signature
            },
         } );

         Future->done(1);
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
