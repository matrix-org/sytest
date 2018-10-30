my $fixture = local_user_fixture();

my $current_version; # FIXME: is there a better way of passing the backup version between tests?

test "Can create backup version",
   requires => [ $fixture ],

   proves => [qw( can_create_backup_version )],

   do => sub {
      my ( $user ) = @_;

      my $version;

      matrix_create_key_backup( $user )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, "version" );
         $version = $content->{version};

         matrix_get_key_backup_info( $user );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, "algorithm" );

         assert_json_keys( $content, "auth_data" );

         $content->{algorithm} eq "m.megolm_backup.v1" or
            die "Expected algorithm to match submitted data";

         $content->{auth_data} eq "anopaquestring" or
            die "Expected auth_data to match submitted data";

         assert_eq( $content->{version}, $version );

         Future->done(1);
      });
   };

test "Responds correctly when backup is empty",
   requires => [ $fixture, qw( can_create_backup_version ) ],

   do => sub {
      my ( $user ) = @_;
      my $version;

      matrix_get_key_backup_info( $user )->then( sub {
         my ( $content ) = @_;

         log_if_fail "Content", $content;

         $version = $content->{version};

         matrix_get_backup_key( $user, '!notaroom', 'notassession', $version);
      })->main::expect_http_4xx
      ->then( sub {
         matrix_get_backup_key( $user, '!notaroom', '', $version);
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "Content", $content;

         assert_deeply_eq( $content, {"sessions" => {}});

         matrix_get_backup_key( $user, '', '', $version );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "Content", $content;

         assert_deeply_eq( $content, {"rooms" => {}});

         Future->done(1);
      });
   };

test "Can backup keys",
   requires => [ $fixture, qw( can_create_backup_version ) ],

   proves => [qw( can_backup_e2e_keys )],

   do => sub {
      my ( $user ) = @_;
      my $version;

      matrix_create_key_backup( $user )->then( sub {
         my ( $content ) = @_;

         $version = $content->{version};

         matrix_backup_keys( $user, '!abcd', '1234', $version, {
               first_message_index => 3,
               forwarded_count     => 0,
               is_verified         => JSON::false,
               session_data        => "anopaquestring",
            },
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         matrix_get_backup_key( $user, '!abcd', '1234', $version );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, qw( first_message_index forwarded_count is_verified session_data ) );

         assert_eq( $content->{first_message_index}, 3, "Expected first message index to match submitted data" );

         assert_eq( $content->{forwarded_count}, 0, "Expected forwarded count to match submitted data" );

         assert_eq( $content->{is_verified}, JSON::false, "Expected is_verified to match submitted data" );

         assert_eq( $content->{session_data}, "anopaquestring", "Expected session data to match submitted data" );

         Future->done(1);
      });
   };

test "Can update keys with better versions",
   requires => [ $fixture, qw( can_backup_e2e_keys ) ],

   proves => [qw( can_update_e2e_keys )],

   do => sub {
      my ( $user ) = @_;
      my $version;

      matrix_create_key_backup( $user )->then( sub {
         my ( $content ) = @_;

         $version = $content->{version};

         matrix_backup_keys( $user, '!abcd', '1234', $version, {
               first_message_index => 2,
               forwarded_count     => 0,
               is_verified         => JSON::false,
               session_data        => "anotheropaquestring",
            },
         );
      })->then( sub {
         matrix_backup_keys( $user, '!abcd', '1234', $version, {
               first_message_index => 1,
               forwarded_count     => 0,
               is_verified         => JSON::false,
               session_data        => "anotheropaquestring",
            },
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         matrix_get_backup_key( $user, '!abcd', '1234', $version );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, qw( first_message_index forwarded_count is_verified session_data ) );

         assert_eq( $content->{first_message_index}, 1, "Expected first message index to match submitted data" );

         assert_eq( $content->{forwarded_count}, 0, "Expected forwarded count to match submitted data" );

         assert_eq( $content->{is_verified}, JSON::false, "Expected is_verified to match submitted data" );

         assert_eq(  $content->{session_data}, "anotheropaquestring", "Expected session data to match submitted data" );

         Future->done(1);
      });
   };

test "Will not update keys with worse versions",
   requires => [ $fixture, qw( can_update_e2e_keys ) ],

   proves => [qw( wont_update_e2e_keys )],

   do => sub {
      my ( $user ) = @_;
      my $version;

      matrix_create_key_backup( $user )->then( sub {
         my ( $content ) = @_;

         $version = $content->{version};

         matrix_backup_keys( $user, '!abcd', '1234', $version, {
               first_message_index => 2,
               forwarded_count     => 0,
               is_verified         => JSON::false,
               session_data        => "anotheropaquestring",
            },
         );
      })->then( sub {
         matrix_backup_keys( $user, '!abcd', '1234', $version, {
               first_message_index => 3,
               forwarded_count     => 0,
               is_verified         => JSON::false,
               session_data        => "anotheropaquestring",
            },
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         matrix_get_backup_key( $user, '!abcd', '1234', $version );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, qw( first_message_index forwarded_count is_verified session_data ) );

         # The data should not be overwritten, so should be the same as what
         # was set by the previous test.
         assert_eq( $content->{first_message_index}, 2, "Expected first message index to match submitted data" );

         assert_eq( $content->{forwarded_count}, 0, "Expected forwarded count to match submitted data" );

         assert_eq( $content->{is_verified}, JSON::false, "Expected is_verified to match submitted data" );

         assert_eq( $content->{session_data}, "anotheropaquestring", "Expected session data to match submitted data" );

         Future->done(1);
      });
   };

test "Will not back up to an old backup version",
   requires => [ $fixture, qw( can_create_backup_version ) ],

   proves => [qw( wont_backup_to_old_version )],

   do => sub {
      my ( $user ) = @_;
      my $old_version;

      matrix_create_key_backup( $user )->then( sub {
         my ( $content ) = @_;

         $old_version = $content->{version};

         matrix_create_key_backup( $user );
      })->then( sub {
         matrix_backup_keys( $user, '!abcd', '1234', $old_version, {
               first_message_index => 3,
               forwarded_count     => 0,
               is_verified         => JSON::false,
               session_data        => "anotheropaquestring",
            },
         );
      })->main::expect_http_4xx
      ->then_done(1);
   };

test "Can delete backup",
   requires => [ $fixture, qw( can_create_backup_version ) ],

   do => sub {
      my ( $user ) = @_;
      my $first_version;
      my $second_version;

      matrix_create_key_backup( $user )->then( sub {
         my ( $content ) = @_;
         $first_version = $content->{version};

         matrix_create_key_backup( $user );
      })->then( sub {
         my ( $content ) = @_;
         $second_version = $content->{version};

         matrix_delete_key_backup( $user, $second_version );
      })->then( sub {
         matrix_get_key_backup_info( $user );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         my $new_version = $content->{version};

         assert_eq( $new_version, $first_version );

         matrix_get_key_backup_info ( $user, $second_version );
      })->main::expect_http_404;
   };

test "Deleted & recreated backups are empty",
   requires => [ $fixture, qw( can_create_backup_version ) ],

   do => sub {
      my ( $user ) = @_;

      my $version;

      matrix_create_key_backup( $user )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, "version" );

         $version = $content->{version};

         log_if_fail "Created version $version";

         matrix_backup_keys( $user, '!abcd', '1234', $version, {
               first_message_index => 3,
               forwarded_count     => 0,
               is_verified         => JSON::false,
               session_data        => "areallyopaquestring",
            },
         );
      })->then( sub {
         log_if_fail "Deleting version $version";

         matrix_delete_key_backup( $user, $version );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         matrix_create_key_backup( $user );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Created version $content->{version}";

         # get all keys
         do_request_json_for( $user,
            method  => "GET",
            uri     => "/unstable/room_keys/keys",
            params  => {
               version => $content->{version},
            }
         );
      })->then( sub {
         my ( $content ) = @_;

         assert_deeply_eq($content, {"rooms" => {}}, "Expected new backup to be empty");

         Future->done(1);
      });
   };


=head2 matrix_create_key_backup

   matrix_create_key_backup( $user )

Create a new key backup version

=cut

sub matrix_create_key_backup {
   my ( $user ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/unstable/room_keys/version",
      content => {
         algorithm => "m.megolm_backup.v1",
         auth_data => "anopaquestring",
      }
   )
}

=head2 matrix_delete_key_backup

   matrix_delete_key_backup( $user, $version )

Delete a key backup version

=cut

sub matrix_delete_key_backup {
   my ( $user, $version ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/unstable/room_keys/version/$version",
   );
}


=head2 matrix_get_key_backup_info

   matrix_get_key_backup_info( $user, $version )

Fetch the metadata about a key backup version, or the latest
version if version is omitted

=cut

sub matrix_get_key_backup_info {
   my ( $user, $version ) = @_;

   my $url = "/unstable/room_keys/version";

   if (defined($version)) {
      $url .= "/$version";
   }

   do_request_json_for( $user,
      method  => "GET",
      uri     => $url,
   )
}

=head2 matrix_backup_keys

   matrix_backup_keys( $user, $room_id, $session_id, $version, $content )

Send keys to a given key backup version

=cut

sub matrix_backup_keys {
   my ( $user, $room_id, $session_id, $version, $content ) = @_;
   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/room_keys/keys/$room_id/$session_id",
      params  => {
         version => $version,
      },
      content => $content,
   )
}

=head2 matrix_get_backup_key

   matrix_get_backup_key( $user, $room_id, $session_id, $version )

Send keys to a given key backup version

=cut

sub matrix_get_backup_key {
   my ( $user, $room_id, $session_id, $version ) = @_;

   my $uri;

   if ($session_id) {
      $uri = "/unstable/room_keys/keys/$room_id/$session_id";
   } elsif ($room_id) {
      $uri = "/unstable/room_keys/keys/$room_id";
   } else {
      $uri = "/unstable/room_keys/keys";
   }

   do_request_json_for( $user,
      method  => "GET",
      uri     => $uri,
      params  => {
         version => $version,
      },
   );
}
