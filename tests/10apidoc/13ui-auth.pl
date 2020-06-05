use JSON qw( decode_json );
use URI::Escape;

our @EXPORT = qw( wait_for_cas_request );

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

# Generate a ticket-submission request from the client to the homeserver.
#
# Waits for the validation request from the homeserver, and returns the given response.
sub make_ticket_request
{
   my ( $http, $homeserver_info, $session, $ticket, $response ) = @_;

   # Note that we skip almost all of the CAS flow since it isn't important
   # for this test. The user just needs to end up back at the homeserver
   # with a valid ticket (and the original UI Auth session ID).
   my $login_uri = $homeserver_info->client_location . "/_matrix/client/r0/login/cas/ticket?session=$session&ticket=$ticket";

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
   requires => [ local_user_fixture() ],

   do => sub {
      my ( $user ) = @_;

      my $DEVICE_ID = "login_device";

      matrix_login_again_with_user(
         $user,
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
   ],

   do => sub {
      my ( $user, $http, $homeserver_info ) = @_;

      my $DEVICE_ID = "login_device";

      my ($user_localpart) = $user->user_id =~ m/@([^:]*):/;
      my $CAS_SUCCESS = <<"EOF";
<cas:serviceResponse xmlns:cas='http://www.yale.edu/tp/cas'>
    <cas:authenticationSuccess>
         <cas:user>$user_localpart</cas:user>
         <cas:attributes></cas:attributes>
    </cas:authenticationSuccess>
</cas:serviceResponse>
EOF

      # the ticket our mocked-up CAS server "generates"
      my $CAS_TICKET = "goldenticket";
      my $session;

      # Create a device.
      matrix_login_again_with_user(
         $user,
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

         make_ticket_request( $http, $homeserver_info, $session, $CAS_TICKET, $CAS_SUCCESS );
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
   ],

   do => sub {
      my ( $user, $http, $homeserver_info ) = @_;

      my $DEVICE_ID = "login_device";

      # The user below is what is returned from SSO and does not match the user
      # being logged into the homeserver.
      my $CAS_SUCCESS = <<'EOF';
<cas:serviceResponse xmlns:cas='http://www.yale.edu/tp/cas'>
    <cas:authenticationSuccess>
         <cas:user>cas_user</cas:user>
         <cas:attributes></cas:attributes>
    </cas:authenticationSuccess>
</cas:serviceResponse>
EOF

      # the ticket our mocked-up CAS server "generates"
      my $CAS_TICKET = "goldenticket";
      my $session;

      # Create a device.
      matrix_login_again_with_user(
         $user,
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

         make_ticket_request( $http, $homeserver_info, $session, $CAS_TICKET, $CAS_SUCCESS );
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
