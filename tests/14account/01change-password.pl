my $password = "my secure password";


test "After changing password, can't log in with old password",
   requires => [ local_user_fixture( password => $password ) ],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/account/password",
         content => {
            auth => {
               type => "m.login.password",
               user     => $user->user_id,
               password => $password,
            },
            new_password => "my new password",
         },
      )->then( sub {
         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/login",

            content => {
               type     => "m.login.password",
               user     => $user->user_id,
               password => $password,
            }
         # We don't mandate the exact failure code here
         # (that should be done in the login test if
         # anywhere), any 4xx code is fine as far as
         # this test is concerned.
         )->main::expect_http_4xx;
      })->then_done(1);
   };

test "After changing password, can log in with new password",
   requires => [ local_user_fixture( password => $password ) ],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/account/password",
         content => {
            auth => {
               type => "m.login.password",
               user     => $user->user_id,
               password => $password,
            },
            new_password => "my new password",
         },
      )->then( sub {
         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/login",

            content => {
               type     => "m.login.password",
               user     => $user->user_id,
               password => "my new password",
            }
         );
      }
      )->then_done(1);
   };

test "After changing password, existing session still works",
   requires => [ local_user_fixture( password => $password ) ],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/account/password",
         content => {
            auth => {
               type => "m.login.password",
               user     => $user->user_id,
               password => $password,
            },
            new_password => "my new password",
         },
      )->then( sub {
         matrix_sync( $user );
      })->then_done(1);
   };

test "After changing password, a different session no longer works",
   requires => [ local_user_fixture( password => $password ) ],

   check => sub {
      my ( $user ) = @_;

      my $other_login;

      matrix_login_again_with_user( $user )->then( sub {
         ( $other_login ) = @_;
         # ensure other login works to start with
         matrix_sync( $other_login );
      })->then( sub {
         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/account/password",
            content => {
               auth => {
                  type => "m.login.password",
                  user     => $user->user_id,
                  password => $password,
               },
               new_password => "my new password",
            });
      })->then( sub {
         matrix_sync( $other_login )->main::expect_http_401;
      })->then_done(1);
   };

test "Pushers created with a different access token are deleted on password change",
   requires => [ local_user_fixture( password => $password ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_login_again_with_user( $user )->then( sub {
         my ( $other_login ) = @_;

         do_request_json_for( $other_login,
            method  => "POST",
            uri     => "/r0/pushers/set",
            content => {
               profile_tag         => "tag",
               kind                => "http",
               app_id              => "sytest",
               app_display_name    => "sytest_display_name",
               device_display_name => "device_display_name",
               pushkey             => "a_push_key",
               lang                => "en",
               data                => {
                  url => "https://dummy.url/is/dummy",
               },
            },
         );
      })->then( sub {
         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/account/password",
            content => {
               auth => {
                  type => "m.login.password",
                  user     => $user->user_id,
                  password => $password,
               },
               new_password => "my new password",
            });
      })->then( sub {
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/pushers/set",
            content => {
               kind    => JSON::null,
               app_id  => "sytest",
               pushkey => "a_push_key",
            },
         )->main::expect_http_404;
      })->then_done(1);
   };

test "Pushers created with a the same access token are not deleted on password change",
   requires => [ local_user_fixture( password => $password ) ],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/r0/pushers/set",
         content => {
            profile_tag         => "tag",
            kind                => "http",
            app_id              => "sytest",
            app_display_name    => "sytest_display_name",
            device_display_name => "device_display_name",
            pushkey             => "a_push_key",
            lang                => "en",
            data                => {
               url => "https://dummy.url/is/dummy",
            },
         },
      )->then( sub {
         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/account/password",
            content => {
               auth => {
                  type => "m.login.password",
                  user     => $user->user_id,
                  password => $password,
               },
               new_password => "my new password",
            });
      })->then( sub {
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/pushers/set",
            content => {
               kind    => JSON::null,
               app_id  => "sytest",
               pushkey => "a_push_key",
            },
         );
      })->then_done(1);
   };

