use JSON qw( decode_json );
use URI::Escape;

our @EXPORT = qw( wait_for_cas_request generate_cas_response matrix_login_with_cas cas_login_fixture );

# A fixture to ensure that CAS is enabled before attempting to run tests against
# a homeserver.
sub cas_login_fixture {
   fixture(
      requires => [ $main::API_CLIENTS[0] ],

      setup    => sub {
         my ($http) = @_;

         $http->do_request_json(
            method => "GET",
            uri    => "/r0/login",
         )->then(sub {
            my ($body) = @_;

            assert_json_keys($body, qw(flows));
            assert_json_list $body->{flows};

            die "SKIP: no m.login.cas" unless
               any {$_->{type} eq "m.login.cas"} @{$body->{flows}};

            Future->done(1);
         });
      },
   );
}

# Generates the XML response that the CAS server would generate in response to
# a query from the homeserver.
#
# It takes a single parameter:
# * The user ID, this can be a Matrix ID (in which case it is stripped to just
#   the localpart) or a plain string to insert into the XML.
sub generate_cas_response
{
   my ( $user_id ) = @_;

   if ($user_id =~ /^@/) {
      ($user_id) = $user_id =~ m/@([^:]*):/;
   }

   my $cas_success = <<"EOF";
<cas:serviceResponse xmlns:cas='http://www.yale.edu/tp/cas'>
    <cas:authenticationSuccess>
         <cas:user>$user_id</cas:user>
         <cas:attributes></cas:attributes>
    </cas:authenticationSuccess>
</cas:serviceResponse>
EOF

   return $cas_success
}

# A convenience function which wraps await_http_request. It returns a successful
# CAS response when queried for a particular path.
#
# This takes two parameters:
#  * The expected path of the request the homeserver makes to the CAS server.
#  * A hash of parameters with the following (optional) keys:
#    * response: The HTTP response body to return to the homeserver request.
sub wait_for_cas_request
{
   my ( $expected_path, %params ) = @_;

   await_http_request( $expected_path, sub {
      return 1;
   })->then( sub {
      my ( $request ) = @_;

      my $response = HTTP::Response->new( 200 );
      $response->add_content( $params{response} // "" );
      $response->content_type( "text/plain" );
      $response->content_length( length $response->content );
      $request->respond( $response );

      Future->done( $request );
   });
}

# Log into Synapse via CAS.
#
# This takes the following parameters:
#  * The Matrix user ID to log in with.
#  * The CAS ticket to use. This can be any string.
#  * The HTTP object.
#  * The Homeserver Info object.
#  * The XML CAS response. See generate_cas_response.
#  * Any additional parameters will be passed as part of the login request.
sub matrix_login_with_cas
{
   my ( $user_id, $http, $homeserver_info, $cas_response, %params ) = @_;

   # the redirectUrl we send to /login/sso/redirect, which is where we
   # hope to get redirected back to
   my $REDIRECT_URL = "https://client?p=http%3A%2F%2Fserver";

   my $HS_URI = $homeserver_info->client_location . "/_matrix/client/r0/login/cas/ticket?redirectUrl=" . uri_escape($REDIRECT_URL);

   # the ticket our mocked-up CAS server "generates"
   my $CAS_TICKET = "goldenticket";

   # step 1: client sends request to /login/sso/redirect
   # step 2: synapse should redirect to the cas server.
   Future->needs_all(
      wait_for_cas_request( "/cas/login" ),
      $http->do_request(
         method => "GET",
         uri    => "/r0/login/sso/redirect",
         params => {
            redirectUrl => $REDIRECT_URL,
         },
      ),
   )->then( sub {
      my ( $cas_request, $_cas_response ) = @_;
      log_if_fail( "Initial CAS request query:",
                   $cas_request->query_string );

      assert_eq( $cas_request->method, "GET", "CAS request method" );

      my $service = $cas_request->query_param( "service" );

      # step 3: client sends credentials to CAS server
      # step 4: CAS redirects, with a ticket number, back to synapse.
      #
      # For this test, we skip this bit, as it's nothing to do with synapse,
      # really.
      #
      # The URI that CAS redirects back to is the value of the 'service'
      # param we gave it, with an additional "ticket" query-param:
      my $login_uri = $service . "&ticket=$CAS_TICKET";

      # step 5: synapse receives ticket number from client, and makes a
      # request to CAS to validate the ticket.
      # step 6: synapse sends a redirect back to the browser, with a
      # 'loginToken' parameter
      Future->needs_all(
         wait_for_cas_request(
            "/cas/proxyValidate",
            response => $cas_response,
         ),
         $http->do_request_json(
            method   => "GET",
            full_uri => $login_uri,
            max_redirects => 0, # don't follow the redirect
         ),
      );
   })->then( sub {
      my ( $cas_validate_request, $ticket_response ) = @_;

      assert_eq( $cas_validate_request->method, "GET",
                 "/cas/proxyValidate request method" );
      assert_eq( $cas_validate_request->query_param( "ticket" ),
                 $CAS_TICKET,
                 "Ticket supplied to /cas/proxyValidate" );
      assert_eq( $cas_validate_request->query_param( "service" ),
                 $HS_URI,
                 "Service supplied to /cas/proxyValidate" );

      assert_ok( $ticket_response =~ "loginToken=([^\"&]+)",
                 "Login token provided in the /ticket response" );
      my $login_token = $1;

      log_if_fail( "Ticket response:", $ticket_response );
      log_if_fail( "Login token:", $login_token );

      # step 7: the client uses the loginToken via the /login API.
      $http->do_request_json(
         method => "POST",
         uri    => "/r0/login",

         content => {
            type     => "m.login.token",
            token    => $login_token,
            %params,
         }
      );
   })->then( sub {
      my ( $body ) = @_;

      log_if_fail( "Response from /login", $body );

      assert_json_keys( $body, qw( access_token home_server user_id device_id ));

      assert_eq( $body->{home_server}, $http->server_name,
                 'home_server in /login response' );
      assert_eq( $body->{user_id}, $user_id,
                 'user_id in /login response' );

      Future->done(1);
   });
}

# Generate a ticket-submission request from the client to the homeserver.
#
# Waits for the validation request from the homeserver, and returns the given response.
sub make_ticket_request
{
   my ( $http, $homeserver_info, $session, $response ) = @_;

   my $CAS_TICKET = "goldenticket";

   # Note that we skip almost all of the CAS flow since it isn't important
   # for this test. The user just needs to end up back at the homeserver
   # with a valid ticket (and the original UI Auth session ID).
   my $login_uri = $homeserver_info->client_location . "/_matrix/client/r0/login/cas/ticket?session=$session&ticket=$CAS_TICKET";

   Future->needs_all(
      wait_for_cas_request(
         "/cas/proxyValidate",
         response => $response,
      ),
      $http->do_request_json(
         method   => "GET",
         full_uri => $login_uri,
         max_redirects => 0, # don't follow the redirect
      ),
   );
}

test "Interactive authentication types include SSO",
   requires => [ local_user_fixture(), $main::API_CLIENTS[0], $main::HOMESERVER_INFO[0], cas_login_fixture(), ],

   do => sub {
      my ( $user, $http, $homeserver_info ) = @_;

      my $DEVICE_ID = "login_device";

      matrix_login_with_cas(
         $user->user_id,
         $http,
         $homeserver_info,
         generate_cas_response( $user->user_id ),
         device_id => $DEVICE_ID,
         initial_device_display_name => "device display",
      )->then( sub {
         # Initiate the interactive authentication session.
         matrix_delete_device( $user, $DEVICE_ID, {} );
      })->main::expect_http_401->then( sub {
         my ($resp) = @_;

         my $body = decode_json $resp->content;

         log_if_fail "Response to empty body", $body;

         assert_json_keys($body, qw(session params flows));
         assert_json_list $body->{flows};

         # Note that this uses the unstable value.
         die "m.login.sso was not listed" unless
            any { $_->{stages}[0] eq "m.login.sso" } @{ $body->{flows} };

         Future->done( 1 );
      });
   };

test "Can perform interactive authentication with SSO",
   requires => [
      local_user_fixture(),
      $main::API_CLIENTS[0],
      $main::HOMESERVER_INFO[0],
      cas_login_fixture(),
   ],

   do => sub {
      my ( $user, $http, $homeserver_info ) = @_;

      my $DEVICE_ID = "login_device";

      my $CAS_SUCCESS = generate_cas_response( $user->user_id );

      my $session;

      # Create a device.
      matrix_login_with_cas(
         $user->user_id,
         $http,
         $homeserver_info,
         generate_cas_response( $user->user_id ),
         device_id => $DEVICE_ID,
         initial_device_display_name => "device display",
      )->then( sub {
         # Initiate the interactive authentication session via device deletion.
         matrix_delete_device( $user, $DEVICE_ID, {} );
      })->main::expect_http_401->then( sub {
         my ( $resp ) = @_;

         my $body = decode_json $resp->content;

         log_if_fail "Response to empty body", $body;

         assert_json_keys( $body, qw( session params flows ));

         $session = $body->{session};

         make_ticket_request( $http, $homeserver_info, $session, $CAS_SUCCESS );
      })->then( sub {
         # Repeat the device deletion, which should now complete.
         matrix_delete_device( $user, $DEVICE_ID, {
            auth => {
               session => $session,
            },
         });
      })->then( sub {
         # the device should be deleted.
         matrix_get_device( $user, $DEVICE_ID )->main::expect_http_404;
      });
   };

test "The user must be consistent through an interactive authentication session with SSO",
   requires => [
      local_user_fixture(),
      $main::API_CLIENTS[0],
      $main::HOMESERVER_INFO[0],
      cas_login_fixture(),
   ],

   do => sub {
      my ( $user, $http, $homeserver_info ) = @_;

      my $DEVICE_ID = "login_device";

      my $session;

      # Create a device.
      matrix_login_with_cas(
         $user->user_id,
         $http,
         $homeserver_info,
         generate_cas_response( $user->user_id ),
         device_id => $DEVICE_ID,
         initial_device_display_name => "device display",
      )->then( sub {
         # Initiate the interactive authentication session via device deletion.
         matrix_delete_device( $user, $DEVICE_ID, {} );
      })->main::expect_http_401->then( sub {
         my ( $resp ) = @_;

         my $body = decode_json $resp->content;

         log_if_fail "Response to empty body", $body;

         assert_json_keys( $body, qw( session params flows ));

         $session = $body->{session};

         make_ticket_request(
            $http,
            $homeserver_info,
            $session,
            # The user below is what is returned from SSO and does not match the user
            # which logged into the homeserver.
            generate_cas_response( "cas_user" ),
         );
      })->then( sub {
         # Repeat the device deletion, which should now give an auth error.
         matrix_delete_device( $user, $DEVICE_ID, {
            auth => {
               session => $session,
            },
         })->main::expect_http_403;
      })->then( sub {
         # The device delete was rejected (the device should still exist).
         matrix_get_device( $user, $DEVICE_ID );
      })->then( sub {
         my ( $device ) = @_;
         assert_json_keys(
            $device,
            qw( device_id user_id display_name ),
         );
         assert_eq( $device->{device_id}, $DEVICE_ID );
         assert_eq( $device->{display_name}, "device display" );
         Future->done( 1 );
      });
   };


test "The operation must be consistent through an interactive authentication session",
   requires => [ local_user_fixture() ],

   do => sub {
      my ( $user ) = @_;

      my $DEVICE_ID = "login_device";
      my $SECOND_DEVICE_ID = "second_device";

      # Create two devices.
      matrix_login_again_with_user(
         $user,
         device_id => $DEVICE_ID,
         initial_device_display_name => "device display",
      )->then( sub {
         matrix_login_again_with_user(
            $user,
            device_id => $SECOND_DEVICE_ID,
            initial_device_display_name => "device display",
         )
      })->then( sub {
         # Initiate the interactive authentication session with the first device.
         matrix_delete_device( $user, $DEVICE_ID, {} );
      })->main::expect_http_401->then( sub {
         my ( $resp ) = @_;

         my $body = decode_json $resp->content;

         log_if_fail "Response to empty body", $body;

         assert_json_keys( $body, qw( session params flows ));

         # Continue the interactive authentication session (by providing
         # credentials), but attempt to delete the second device.
         matrix_delete_device( $user, $SECOND_DEVICE_ID, {
             auth => {
                type     => "m.login.password",
                user     => $user->user_id,
                password => $user->password,
                session  => $body->{session},
             }
         })->main::expect_http_403;
      })->then( sub {
         # The device delete was rejected (the device should still exist).
         matrix_get_device( $user, $SECOND_DEVICE_ID );
      })->then( sub {
         my ( $device ) = @_;
         assert_json_keys(
            $device,
            qw( device_id user_id display_name ),
         );
         assert_eq( $device->{device_id}, $SECOND_DEVICE_ID );
         assert_eq( $device->{display_name}, "device display" );
         Future->done( 1 );
      });
   };
