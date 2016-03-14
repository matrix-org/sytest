my $password = "my secure password";


test "After changing password, can't log in with old password",
   requires => [ local_user_fixture( password => $password ) ],

   check => sub {
      my ( $user, ) = @_;

      my $http = $user->http;

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
         $http->do_request_json(
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
      }
      )->then_done(1);
   };

test "After changing password, can log in with new password",
   requires => [ local_user_fixture( password => $password ) ],

   check => sub {
      my ( $user, ) = @_;

      my $http = $user->http;

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
         $http->do_request_json(
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
      my ( $user, ) = @_;

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
      my ( $user, ) = @_;

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

# TODO: Also possibly test that pushers are deleted iff they were created with different access token
