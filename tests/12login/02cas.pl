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

my $CAS_SUCCESS = <<'EOF';
<cas:serviceResponse xmlns:cas='http://www.yale.edu/tp/cas'>
    <cas:authenticationSuccess>
         <cas:user>cas_user</cas:user>
         <cas:attributes></cas:attributes>
    </cas:authenticationSuccess>
</cas:serviceResponse>
EOF

test "login types include SSO",
   requires => [ $main::API_CLIENTS[0] ],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         uri => "/r0/login",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( flows ));
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list";

         die "m.login.sso was not listed" unless
            any { $_->{type} eq "m.login.sso" } @{ $body->{flows} };

         Future->done( 1 );
      });
   };


my $cas_login_fixture = fixture(
   requires => [ $main::API_CLIENTS[0] ],

   setup => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         uri => "/r0/login",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( flows ));
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list";

         die "SKIP: no m.login.cas" unless
            any { $_->{type} eq "m.login.cas" } @{ $body->{flows} };

         Future->done( 1 );
      });
   },
);


test "/login/cas/redirect redirects if the old m.login.cas login type is listed",
   requires => [
      $main::TEST_SERVER_INFO, $main::API_CLIENTS[0], $cas_login_fixture,
   ],

   do => sub {
      my ( $test_server_info, $http ) = @_;

      my $REDIRECT_URL = "https://client?p=http%3A%2F%2Fserver";

      $http->do_request(
         method => "GET",
         uri    => "/r0/login/cas/redirect",
         params => {
            redirectUrl => $REDIRECT_URL,
         },
         max_redirects => 0,
      )->main::expect_http_302->then( sub {
         my ( $resp ) = @_;
         my $loc = $resp->header( "Location" );
         my $expected = $test_server_info->client_location . "/cas/login?";
         die "unexpected location '$loc' (expected '$expected...')" unless
            $loc =~ /^\Q$expected/;
         Future->done(1);
      });
   };

test "Can login with new user via CAS",
   requires => [
      $main::API_CLIENTS[0],
      $main::HOMESERVER_INFO[0],
   ],

   do => sub {
      my ( $http, $homeserver_info ) = @_;

      my $HS_URI = $homeserver_info->client_location;

      # the redirectUrl we send to /login/cas/redirect, which is where we
      # hope to get redirected back to
      my $REDIRECT_URL = "https://client?p=http%3A%2F%2Fserver";

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
         my ( $cas_request, $cas_response ) = @_;
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
               response => $CAS_SUCCESS,
            ),
            $http->do_request_json(
               method   => "GET",
               full_uri => $login_uri,
               max_redirects => 0, # don't follow the redirect
            )->followed_by( \&main::expect_http_302 ),
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

         my $redirect = $ticket_response->header( "Location" );
         log_if_fail( "Redirect from /login/cas/ticket", $redirect);
         assert_ok( $redirect =~ m#^https://client\?#,
                    "Location returned by /login/cas/ticket did not match" );

         # the original query param should have been preserved
         my $redirect_uri = URI->new($redirect);
         assert_eq( $redirect_uri->query_param( "p" ) // undef,
                    "http://server",
                    "Query param on redirect from /login/cas/ticket" );

         # a 'loginToken' should be added.
         my $login_token = $redirect_uri->query_param( "loginToken" );

         # step 7: the client uses the loginToken via the /login API.
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/login",

            content => {
               type     => "m.login.token",
               token    => $login_token,
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail( "Response from /login", $body );

         assert_json_keys( $body, qw( access_token home_server user_id device_id ));

         assert_eq( $body->{home_server}, $http->server_name,
                    'home_server in /login response' );
         assert_eq( $body->{user_id},
                    '@cas_user:' . $http->server_name,
                    'user_id in /login response' );

         Future->done(1);
      });
   };
