# these two functions are stolen from 06-device-lists.pl
sub is_user_in_changed_list
{
   my ( $user, $body ) = @_;

   return $body->{device_lists} &&
          $body->{device_lists}{changed} &&
          any { $_ eq $user->user_id } @{ $body->{device_lists}{changed} };
}


# returns a Future which resolves to the body of the sync result which contains
# the change notification
sub sync_until_user_in_device_list
{
   my ( $syncing_user, $user_to_wait_for, %params ) = @_;

   my $device_list = $params{device_list} // 'changed';
   my $msg = $params{msg} // 'sync_until_user_in_device_list';

   my $wait_for_id = $user_to_wait_for->user_id;

   # my $trace = Devel::StackTrace->new(no_args => 1);
   # log_if_fail $trace->frame(1)->as_string();

   $msg = "$msg: waiting for $wait_for_id in $device_list";

   return repeat_until_true {
      matrix_sync_again( $syncing_user, timeout => 1000 )
      ->then( sub {
         my ( $body ) = @_;

         log_if_fail "$msg: body", $body;

         my $res = $body->{device_lists} &&
            $body->{device_lists}{$device_list} &&
            any { $_ eq $wait_for_id } @{ $body->{device_lists}{$device_list} };

         Future->done( $res && $body );
      });
   };
}

test "Can store and retrieve attestations",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_upload_e2e_keys ) ],

   proves => [qw( can_store_attestations )],

   do => sub {
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user1_device = $user1->device_id;
      my $user2_id = $user2->user_id;
      my $user2_device = $user2->device_id;

      matrix_upload_device_key( $user2 )->then( sub {
         matrix_store_attestations( $user1, [
               {
                  user_id => $user2_id,
                  device_id => $user2_device,
                  keys => {
                     ed25519 => "ed25519+key"
                  },
                  state => "verified",
                  signatures => {
                     $user1_id => {
                        "ed25519:$user1_device" => "signature+of+user2+key"
                     }
                  }
               },
            ]
         );
      })->then( sub {
         my ( $content ) = @_;

         matrix_get_keys( $user1, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "device keys:", $content;

         assert_json_keys( $content, $user2_device );

         my $device = $content->{$user2_device};

         assert_json_keys( $device, "unsigned" );

         my $unsigned = $device->{unsigned};

         assert_json_keys( $unsigned, "attestations" );

         my $attestations = $unsigned->{attestations};

         assert_json_list($attestations);

         my $found = 0;

         foreach my $attestation (@$attestations) {
            assert_json_keys( $attestation, "user_id", "device_id", "keys", "state", "signatures" );
            my $signatures = $attestation->{signatures};
            if (exists $signatures->{$user1_id}
                && exists $signatures->{$user1_id}{"ed25519:$user1_device"}
                && $signatures->{$user1_id}{"ed25519:$user1_device"} eq "signature+of+user2+key") {
               $found = 1;
               assert_eq($attestation->{user_id}, $user2_id, "Expected target user ID to match submitted data");
               assert_eq($attestation->{device_id}, $user2_device, "Expected device ID to match submitted data");
               assert_deeply_eq($attestation->{keys}, {
                     ed25519 => "ed25519+key"
                  }, "Expected keys to match submitted data");
               assert_eq($attestation->{state}, "verified", "Expected verified state to match submitted data");
            }
         }

         assert_ok($found, "Expected submitted attestation to be found");

         Future->done(1);
      });
   };

test "Filters out attestations not made by the user",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_upload_e2e_keys ) ],

   proves => [qw( can_store_attestations )],

   do => sub {
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user1_device = $user1->device_id;
      my $user2_id = $user2->user_id;
      my $user2_device = $user2->device_id;

      matrix_upload_device_key( $user2 )->then( sub {
         matrix_store_attestations( $user1, [
               {
                  user_id => $user2_id,
                  device_id => $user2_device,
                  keys => {
                     ed25519 => "ed25519+key"
                  },
                  state => "verified",
                  signatures => {
                     $user2_id => {
                        "ed25519:$user2_id" => "signature+of+user2+key"
                     }
                  }
               },
            ],
         );
      })->then( sub {
         my ( $content ) = @_;

         matrix_get_keys( $user1, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "device_keys:", $content;

         assert_json_keys( $content, $user2_device );

         my $device = $content->{$user2_device};

         assert_json_keys( $device, "unsigned" );

         assert_ok(!defined $device->{unsigned}{attestations}, "Expected to have no attestations");

         Future->done(1);
      });
   };

test "Other users cannot see a user's attestations",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_upload_e2e_keys ) ],

   proves => [qw( can_store_attestations )],

   do => sub {
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user1_device = $user1->device_id;
      my $user2_id = $user2->user_id;
      my $user2_device = $user2->device_id;

      matrix_upload_device_key( $user2 )->then( sub {
         matrix_store_attestations( $user1, [
               {
                  user_id => $user2_id,
                  device_id => "ABCDEFG",
                  keys => {
                     ed25519 => "ed25519+key"
                  },
                  state => "verified",
                  signatures => {
                     $user1_id => {
                        "ed25519:ZYXWVUT" => "signature+of+ABCDEFG+key"
                     }
                  }
               },
            ],
         );
      })->then( sub {
         my ( $content ) = @_;

         matrix_get_keys( $user2, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "device_keys:", $content;

         assert_json_keys( $content, $user2_device );

         my $device = $content->{$user2_device};

         assert_json_keys( $device, "unsigned" );

         assert_ok(!defined $device->{unsigned}{attestations}, "Expected to have no attestations");

         Future->done(1);
      });
   };

test "self-attestations appear in /sync (local test)",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ),
                 qw( can_upload_e2e_keys ) ],

   check => sub {
      # a user's self-attestations should show up in everyone's (who shares a
      # room with them) sync stream
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user2_id = $user2->user_id;

      my $room_id;

      matrix_create_room( $user1 )->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_upload_device_key( $user2 );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         matrix_sync( $user2 );
      })->then( sub {
         matrix_store_attestations( $user2, [
               {
                  user_id => $user2_id,
                  device_id => "ABCDEFG",
                  keys => {
                     ed25519 => "ed25519+key"
                  },
                  state => "verified",
                  signatures => {
                     $user2_id => {
                        "ed25519:ZYXWVUT" => "signature+of+ABCDEFG+key"
                     }
                  }
               },
            ],
         );
      })->then( sub {
         matrix_sync_again( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, "device_lists" );
         my $device_lists = $body->{device_lists};

         log_if_fail "user1 device_lists", $device_lists;

         assert_json_keys( $device_lists, "changed" );

         is_user_in_changed_list( $user2, $body )
            or die "user not in changed list";

         matrix_sync_again( $user2 );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, "device_lists" );
         my $device_lists = $body->{device_lists};

         log_if_fail "user2 device_lists", $device_lists;

         assert_json_keys( $device_lists, "changed" );

         is_user_in_changed_list( $user2, $body )
            or die "user not in changed list";

         Future->done(1);
      });
   };

test "local attestations only notify the attesting user in /sync",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_sync ),
                 qw( can_upload_e2e_keys ) ],

   check => sub {
      # only the attesting user should be notified about their own attestations
      # made about someone else's devices
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user2_id = $user2->user_id;

      my $room_id;

      matrix_sync( $user1 )->then(sub {
         matrix_sync( $user2 );
      })->then( sub {
         matrix_create_room( $user1 );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_upload_device_key( $user2 );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         sync_until_user_in_device_list( $user2, $user2 );
      })->then( sub {
         matrix_store_attestations( $user1, [
               {
                  user_id => $user2_id,
                  device_id => "ABCDEFG",
                  keys => {
                     ed25519 => "ed25519+key"
                  },
                  state => "verified",
                  signatures => {
                     $user1_id => {
                        "ed25519:ZYXWVUT" => "signature+of+ABCDEFG+key"
                     }
                  }
               },
            ],
         );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         Future->done(1);
      });
   };

test "Can query remote attestations",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_e2e_keys ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user1_device = $user1->device_id;
      my $user2_id = $user2->user_id;
      my $user2_device = $user2->device_id;

      matrix_upload_device_key( $user2 )->then( sub {
         matrix_store_attestations( $user2, [
               {
                  user_id => $user2_id,
                  device_id => $user2_device,
                  keys => {
                     ed25519 => "ed25519+key"
                  },
                  state => "verified",
                  signatures => {
                     $user2_id => {
                        "ed25519:$user2_device" => "signature+of+user2+key"
                     }
                  }
               },
            ]
         );
      })->then( sub {
         my ( $content ) = @_;

         matrix_get_keys( $user1, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "device keys:", $content;

         assert_json_keys( $content, $user2_device );

         my $device = $content->{$user2_device};

         assert_json_keys( $device, "unsigned" );

         my $unsigned = $device->{unsigned};

         assert_json_keys( $unsigned, "attestations" );

         my $attestations = $unsigned->{attestations};

         assert_json_list($attestations);

         my $found = 0;

         foreach my $attestation (@$attestations) {
            assert_json_keys( $attestation, "user_id", "device_id", "keys", "state", "signatures" );
            my $signatures = $attestation->{signatures};
            if (exists $signatures->{$user2_id}
                && exists $signatures->{$user2_id}{"ed25519:$user2_device"}
                && $signatures->{$user2_id}{"ed25519:$user2_device"} eq "signature+of+user2+key") {
               $found = 1;
               assert_eq($attestation->{user_id}, $user2_id, "Expected target user ID to match submitted data");
               assert_eq($attestation->{device_id}, $user2_device, "Expected device ID to match submitted data");
               assert_deeply_eq($attestation->{keys}, {
                     ed25519 => "ed25519+key"
                  }, "Expected keys to match submitted data");
               assert_eq($attestation->{state}, "verified", "Expected verified state to match submitted data");
            }
         }

         assert_ok($found, "Expected submitted attestation to be found");

         Future->done(1);
      });
   };

test "self-attestations appear in /sync (federation test)",
    requires => [ local_user_fixture(), remote_user_fixture(),
                  qw( can_sync ),
                  qw( can_upload_e2e_keys )],

   check => sub {
      # a user's self-attestations should show up in everyone's (who shares a
      # room with them) sync stream
      my ( $user1, $user2 ) = @_;

      my $user1_id = $user1->user_id;
      my $user1_device = $user1->device_id;
      my $user2_id = $user2->user_id;
      my $user2_device = $user2->device_id;

      my $room_id;

      matrix_upload_device_key( $user2 )->then( sub {
         matrix_create_room( $user1 );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_invite_user_to_room( $user1, $user2, $room_id )
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         matrix_join_room( $user2, $room_id );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         matrix_sync( $user2 );
      })->then( sub {
         matrix_store_attestations( $user2, [
               {
                  user_id => $user2_id,
                  device_id => $user2_device,
                  keys => {
                     ed25519 => "ed25519+key"
                  },
                  state => "verified",
                  signatures => {
                     $user2_id => {
                        "ed25519:$user2_device" => "signature+of+user2+key"
                     }
                  }
               },
            ],
         );
      })->then( sub {
         sync_until_user_in_device_list( $user1, $user2 );
      })->then( sub {
         matrix_get_keys( $user1, $user2_id );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "device keys:", $content;

         assert_json_keys( $content, $user2_device );

         my $device = $content->{$user2_device};

         assert_json_keys( $device, "unsigned" );

         my $unsigned = $device->{unsigned};

         assert_json_keys( $unsigned, "attestations" );

         my $attestations = $unsigned->{attestations};

         assert_json_list($attestations);

         my $found = 0;

         foreach my $attestation (@$attestations) {
            assert_json_keys( $attestation, "user_id", "device_id", "keys", "state", "signatures" );
            my $signatures = $attestation->{signatures};
            if (exists $signatures->{$user2_id}
                && exists $signatures->{$user2_id}{"ed25519:$user2_device"}
                && $signatures->{$user2_id}{"ed25519:$user2_device"} eq "signature+of+user2+key") {
               $found = 1;
               assert_eq($attestation->{user_id}, $user2_id, "Expected target user ID to match submitted data");
               assert_eq($attestation->{device_id}, $user2_device, "Expected device ID to match submitted data");
               assert_deeply_eq($attestation->{keys}, {
                     ed25519 => "ed25519+key"
                  }, "Expected keys to match submitted data");
               assert_eq($attestation->{state}, "verified", "Expected verified state to match submitted data");
            }
         }

         assert_ok($found, "Expected submitted attestation to be found");

         Future->done(1);
      });
   };

=head2 matrix_upload_device_key

   matrix_upload_device_key( $user )

upload a device key

=cut

sub matrix_upload_device_key {
   my ( $user ) = @_;

   do_request_json_for(
      $user,
      method  => "POST",
      uri     => "/unstable/keys/upload",
      content => {
         device_keys => {
            user_id   => $user->user_id,
            device_id => $user->device_id,
         },
         one_time_keys => {
            "my_algorithm:my_id_1" => "my+base64+key"
         }
      }
   );
}


=head2 matrix_store_attestation

   matrix_store_attestation( $user, $attestation )

store an attestation

=cut

sub matrix_store_attestations {
   my ( $user, $attestation ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/unstable/keys/upload",
      content => {
         attestations => $attestation,
      }
   );
}

=head2 matrix_get_attestations

   matrix_get_attestations( $user, $taget_user_id )

Delete a key backup version

=cut

sub matrix_get_keys {
   my ( $user, $target_user_id ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/unstable/keys/query",
      content => {
         device_keys => {
            $target_user_id => []
         }
      }
   )->then( sub {
      my ( $content ) = @_;
      Future->done($content->{"device_keys"}{$target_user_id});
   });
}
