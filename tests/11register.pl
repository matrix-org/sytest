use utf8;
use JSON qw( decode_json );
use URI;

# See also 10apidoc/01register.pl

# This test only tests the recaptcha validation stage, and not
# and actual registration. It also abuses the fact the Synapse
# permits validation of a recaptcha stage even if it's not actually
# required in any of the given auth flows.
multi_test "Register with a recaptcha",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      Future->needs_all(
         await_http_request( "/recaptcha/api/siteverify", sub {1} )
            ->SyTest::pass_on_done( "Got recaptcha verify request" )
         ->then( sub {
            my ( $request ) = @_;

            my $params = $request->body_from_form;

            $params->{secret} eq "sytest_recaptcha_private_key" or
               die "Bad secret";

            $params->{response} eq "sytest_captcha_response" or
               die "Bad response";

            $request->respond_json(
               { success => JSON::true },
            );

            Future->done(1);
         }),

         $http->do_request_json(
            method  => "POST",
            uri     => "/r0/register",
            content => {
               username => $localpart,
               password => "my secret",
               auth     => {
                  type     => "m.login.recaptcha",
                  response => "sytest_captcha_response",
               },
            },
         )->main::expect_http_4xx
         ->then( sub {
            my ( $response ) = @_;

            my $body = decode_json $response->content;

            log_if_fail "Body:", $body;

            assert_json_keys( $body, qw(completed) );
            assert_json_list( my $completed = $body->{completed} );

            @$completed == 1 or
               die "Expected one completed stage";

            $completed->[0] eq "m.login.recaptcha" or
               die "Expected to complete m.login.recaptcha";

            pass "Passed captcha validation";
            Future->done(1);
         }),
      )
   };

test "registration is idempotent, without username specified",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      my $session;
      my $user_id;

      # Start a session
      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            password => "s3kr1t",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         $session = $body->{session};

         # Now register a user
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               password => "s3kr1t",
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         # check that worked okay...
         assert_json_keys( $body, qw( user_id home_server access_token ));

         $user_id = $body->{user_id};

         # now try to register again with the same session
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               password => "s3kr1t",
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         # we should have got an equivalent response
         # (ie. success, and the same user id)
         assert_json_keys( $body, qw( user_id home_server access_token ));

         assert_eq( $body->{user_id}, $user_id );

         Future->done( 1 );
      });
   };

test "registration is idempotent, with username specified",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      my $session;

      # Start a session
      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "s3kr1t",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         $session = $body->{session};

         # Now register a user
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               username => $localpart,
               password => "s3kr1t",
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         # check that worked okay...
         assert_json_keys( $body, qw( user_id home_server access_token ));

         # now try to register again with the same session
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               username => $localpart,
               password => "s3kr1t",
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         # we should have got an equivalent response
         # (ie. success, and the same user id)
         assert_json_keys( $body, qw( user_id home_server access_token ));

         my $actual_user_id = $body->{user_id};
         my $home_server = $body->{home_server};

         assert_eq( $actual_user_id, "\@$localpart:$home_server",
            "registered user ID" );

         Future->done( 1 );
      });
   };

test "registration remembers parameters",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      my $session;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "s3kr1t",
            device_id => "xyzzy",
            initial_device_display_name => "display_name",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         $session = $body->{session};

         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id home_server access_token ));

         my $actual_user_id = $body->{user_id};
         my $home_server = $body->{home_server};

         assert_eq( $actual_user_id, "\@$localpart:$home_server",
            "registered user ID" );

         my $user = new_User(
            http          => $http,
            user_id       => $actual_user_id,
            device_id     => $body->{device_id},
            access_token  => $body->{access_token},
         );
         # check that the right device_id was registered
         matrix_get_device( $user, "xyzzy" );
      })->then( sub {
         my ( $device ) = @_;
         assert_eq( $device->{display_name}, "display_name");
         Future->done( 1 );
      });
   };

test "registration accepts non-ascii passwords",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "übers3kr1t",
            device_id => "xyzzy",
            initial_device_display_name => "display_name",
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         my $session = $body->{session};

         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id home_server access_token ));
         Future->done( 1 );
      });
   };

test "registration with inhibit_login inhibits login",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
      my ( $http, $localpart ) = @_;

      my $session;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            username => $localpart,
            password => "s3kr1t",
            inhibit_login => 1,
         },
      )->main::expect_http_401->then( sub {
         my ( $response ) = @_;

         my $body = decode_json $response->content;

         assert_json_keys( $body, qw( session ));

         $session = $body->{session};

         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => {
               auth     => {
                  session => $session,
                  type    => "m.login.dummy",
               }
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id home_server ));
         foreach ( qw( device_id access_token )) {
            exists $body->{$_} and die "Got an unexpected a '$_' key";
         }

         my $actual_user_id = $body->{user_id};
         my $home_server = $body->{home_server};

         assert_eq( $actual_user_id, "\@$localpart:$home_server",
            "registered user ID" );

         Future->done( 1 );
      });
   };
