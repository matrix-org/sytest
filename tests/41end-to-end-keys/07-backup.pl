my $fixture = local_user_fixture();

my $current_version; # FIXME: is there a better way of passing the backup version between tests?

test "Can create backup version",
   requires => [ $fixture ],

   proves => [qw( can_create_backup_version )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/unstable/room_keys/version",
         content => {
            algorithm => "m.megolm_backup.v1",
            auth_data => "anopaquestring",
         }
      )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, "version" );

         $current_version = $content->{version};

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/unstable/room_keys/version",
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, "algorithm" );

         assert_json_keys( $content, "auth_data" );

         $content->{algorithm} eq "m.megolm_backup.v1" or
            die "Expected algorithm to match submitted data";

         $content->{auth_data} eq "anopaquestring" or
            die "Expected auth_data to match submitted data";

         # FIXME: check that version matches the version returned above

         Future->done(1);
      });
   };

test "Can backup keys",
   requires => [ $fixture, qw( can_create_backup_version ) ],

   proves => [qw( can_backup_e2e_keys )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "PUT",
         uri     => "/unstable/room_keys/keys/!abcd/1234",
         params  => {
            version => $current_version,
         },
         content => {
            first_message_index => 3,
            forwarded_count     => 0,
            is_verified         => JSON::false,
            session_data        => "anopaquestring",
         }
      )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/unstable/room_keys/keys/!abcd/1234",
            params  => {
               version => $current_version,
            }
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, qw( first_message_index forwarded_count is_verified session_data ) );

         $content->{first_message_index} == 3 or
            die "Expected first message index to match submitted data";

         $content->{forwarded_count} == 0 or
            die "Expected forwarded count to match submitted data";

         $content->{is_verified} == JSON::false or
            die "Expected is_verified to match submitted data";

         $content->{session_data} eq "anopaquestring" or
            die "Expected session data to match submitted data";

         Future->done(1);
      });
   };

test "Can update keys with better versions",
   requires => [ $fixture, qw( can_backup_e2e_keys ) ],

   proves => [qw( can_update_e2e_keys )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "PUT",
         uri     => "/unstable/room_keys/keys/!abcd/1234",
         params  => {
            version => $current_version,
         },
         content => {
            first_message_index => 1,
            forwarded_count     => 0,
            is_verified         => JSON::false,
            session_data        => "anotheropaquestring",
         }
      )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/unstable/room_keys/keys/!abcd/1234",
            params  => {
               version => $current_version,
            }
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, qw( first_message_index forwarded_count is_verified session_data ) );

         $content->{first_message_index} == 1 or
            die "Expected first message index to match submitted data";

         $content->{forwarded_count} == 0 or
            die "Expected forwarded count to match submitted data";

         $content->{is_verified} == JSON::false or
            die "Expected is_verified to match submitted data";

         $content->{session_data} eq "anotheropaquestring" or
            die "Expected session data to match submitted data";

         Future->done(1);
      });
   };

test "Will not update keys with worse versions",
   requires => [ $fixture, qw( can_update_e2e_keys ) ],

   proves => [qw( wont_update_e2e_keys )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "PUT",
         uri     => "/unstable/room_keys/keys/!abcd/1234",
         params  => {
            version => $current_version,
         },
         content => {
            first_message_index => 5,
            forwarded_count     => 0,
            is_verified         => JSON::false,
            session_data        => "yetanotheropaquestring",
         }
      )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/unstable/room_keys/keys/!abcd/1234",
            params  => {
               version => $current_version,
            }
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, qw( first_message_index forwarded_count is_verified session_data ) );

         # The data should not be overwritten, so should be the same as what
         # was set by the previous test.
         $content->{first_message_index} == 1 or
            die "Expected first message index to match submitted data";

         $content->{forwarded_count} == 0 or
            die "Expected forwarded count to match submitted data";

         $content->{is_verified} == JSON::false or
            die "Expected is_verified to match submitted data";

         $content->{session_data} eq "anotheropaquestring" or
            die "Expected session data to match submitted data";

         Future->done(1);
      });
   };

test "Will not back up to an old backup version",
   requires => [ $fixture, qw( can_create_backup_version ) ],

   proves => [qw( wont_backup_to_old_version )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/unstable/room_keys/version",
         content => {
            algorithm => "m.megolm_backup.v1",
            auth_data => "anopaquestring",
         }
      )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, "version" );

         my $old_version = $current_version;

         $current_version = $content->{version};

         do_request_json_for( $user,
            method  => "PUT",
            uri     => "/unstable/room_keys/keys/!abcd/1234",
            params  => {
               version => $old_version,
            },
            content => {
               first_message_index => 3,
               forwarded_count     => 0,
               is_verified         => JSON::false,
               session_data        => "anopaquestring",
            }
             );
      })->main::expect_http_4xx
      ->then_done(1);
   };

test "Can delete backup",
   requires => [ $fixture, qw( can_create_backup_version ) ],

   do => sub {
      my ( $user ) = @_;

      log_if_fail "Deleting version: ", $current_version;

      do_request_json_for( $user,
         method  => "GET",
         uri     => "/unstable/room_keys/version",
      )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         do_request_json_for( $user,
            method  => "DELETE",
            uri     => "/unstable/room_keys/version/$current_version",
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/unstable/room_keys/version",
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         do_request_json_for( $user,
            method  => "DELETE",
            uri     => "/unstable/room_keys/version/$content->{version}",
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/unstable/room_keys/version",
         );
      })->main::expect_http_404;
   };

test "Deleted & recreated backups are empty",
   requires => [ $fixture, qw( can_create_backup_version ) ],

   do => sub {
      my ( $user ) = @_;

      my $version;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/unstable/room_keys/version",
         content => {
            algorithm => "m.megolm_backup.v1",
            auth_data => "anevenmoreopaquestring",
         }
      )->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         assert_json_keys( $content, "version" );

         $version = $content->{version};

         log_if_fail "Created version $version";

         do_request_json_for( $user,
            method  => "PUT",
            uri     => "/unstable/room_keys/keys/!abcd/1234",
            params  => {
               version => $version,
            },
            content => {
               first_message_index => 3,
               forwarded_count     => 0,
               is_verified         => JSON::false,
               session_data        => "areallyopaquestring",
            }
         );
      })->then( sub {
         log_if_fail "Deleting version $version";
         do_request_json_for( $user,
            method  => "DELETE",
            uri     => "/unstable/room_keys/version/$version",
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Content", $content;

         do_request_json_for( $user,
            method  => "POST",
            uri     => "/unstable/room_keys/version",
            content => {
               algorithm => "m.megolm_backup.v1",
               auth_data => "omgyouwouldntbelievehowopaquethisstringis",
            }
         );
      })->then( sub {
         my ( $content ) = @_;
         log_if_fail "Created version $content->{version}";

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/unstable/room_keys/keys",
            params  => {
               version => $content->{version},
            }
         );
      })->main::expect_http_404;
   };
