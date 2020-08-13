use Future::Utils qw( repeat );

my $fixture = local_user_fixture();

test "Can create backup version",
   requires => [ $fixture ],

   proves => [qw( can_create_backup_version )],

   do => sub {
      my ( $user ) = @_;

      my $version;

      matrix_create_key_backup( $user )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Create backup: ", $content;

         assert_json_keys( $content, "version" );
         $version = $content->{version};

         matrix_get_key_backup_info( $user );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Get backup info: ", $content;

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

test "Can update backup version",
   requires => [ $fixture ],

   proves => [qw( can_create_backup_version )],

   do => sub {
      my ( $user ) = @_;

      my $version;

      matrix_create_key_backup( $user )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Create backup: ", $content;

         assert_json_keys( $content, "version" );
         $version = $content->{version};

         do_request_json_for(
            $user,
            method  => "PUT",
            uri     => "/r0/room_keys/version/$version",
            content => {
               algorithm => "m.megolm_backup.v1",
               auth_data => "adifferentopaquestring",
               version => $version
            }
         );
      })->then( sub {
         matrix_get_key_backup_info( $user, $version );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Get backup info: ", $content;

         assert_json_keys( $content, "algorithm" );

         assert_json_keys( $content, "auth_data" );

         $content->{algorithm} eq "m.megolm_backup.v1" or
            die "Expected algorithm to match submitted data";

         $content->{auth_data} eq "adifferentopaquestring" or
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

         log_if_fail "Get backup info: ", $content;

         $version = $content->{version};

         # check that asking for a specific session that does not exist returns
         # an M_NOT_FOUND
         matrix_get_backup_key( $user, $version, '!notaroom', 'notassession' );
      })->main::expect_m_not_found
      ->then( sub {
         # check that asking for all the keys in a room returns an empty
         # response rather than an error when nothing has been backed up yet
         matrix_get_backup_key( $user, $version, '!notaroom' );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "Get keys from room: ", $content;

         assert_deeply_eq( $content, { "sessions" => {} } );

         # check that asking for all the keys returns an empty response rather
         # than an error when nothing has been backed up yet
         matrix_get_backup_key( $user, $version );
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "Get all keys: ", $content;

         assert_deeply_eq( $content, { "rooms" => {} } );

         # check that asking for a nonexistent backup version returns an
         # M_NOT_FOUND
         matrix_get_backup_key( $user, 'bogusversion' );
      })->main::expect_m_not_found;
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
         log_if_fail "Back up session: ", $content;

         matrix_get_backup_key( $user, $version, '!abcd', '1234' );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Get session backup: ", $content;

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
         log_if_fail "Back up session: ", $content;

         matrix_get_backup_key( $user, $version, '!abcd', '1234' );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Get session backup: ", $content;

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
         log_if_fail "Back up session: ", $content;

         matrix_get_backup_key( $user, $version, '!abcd', '1234' );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Get session backup: ", $content;

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
         log_if_fail "Get backup: ", $content;

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
         log_if_fail "Create backup: ", $content;

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
         log_if_fail "Delete backup: ", $content;

         matrix_create_key_backup( $user );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Created version $content->{version}";

         # get all keys
         do_request_json_for( $user,
            method  => "GET",
            uri     => "/r0/room_keys/keys",
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

# regression test for https://github.com/matrix-org/synapse/issues/4169
test "Can create more than 10 backup versions",
   requires => [ $fixture ],

   do => sub {
      my ( $user ) = @_;

      repeat( sub {
         matrix_create_key_backup( $user );
      }, foreach => [ 0 .. 10 ], while => sub { $_[0] -> is_done });
   };


=head2 matrix_create_key_backup

   matrix_create_key_backup( $user )

Create a new key backup version

=cut

sub matrix_create_key_backup {
   my ( $user ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/r0/room_keys/version",
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
      uri     => "/r0/room_keys/version/$version",
   );
}


=head2 matrix_get_key_backup_info

   matrix_get_key_backup_info( $user, $version )

Fetch the metadata about a key backup version, or the latest
version if version is omitted

=cut

sub matrix_get_key_backup_info {
   my ( $user, $version ) = @_;

   my $url = "/r0/room_keys/version";

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
      uri     => "/r0/room_keys/keys/$room_id/$session_id",
      params  => {
         version => $version,
      },
      content => $content,
   )
}

=head2 matrix_get_backup_key

   matrix_get_backup_key( $user, $version, $room_id, $session_id )

Get keys from a given key backup version

=cut

sub matrix_get_backup_key {
   my ( $user, $version, $room_id, $session_id ) = @_;

   my $uri;

   if ( defined $session_id ) {
      $uri = "/r0/room_keys/keys/$room_id/$session_id";
   } elsif ( defined $room_id ) {
      $uri = "/r0/room_keys/keys/$room_id";
   } else {
      $uri = "/r0/room_keys/keys";
   }

   do_request_json_for( $user,
      method  => "GET",
      uri     => $uri,
      params  => {
         version => $version,
      },
   );
}
