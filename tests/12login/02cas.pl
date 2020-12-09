use URI::Escape;

my $CAS_SUCCESS = generate_cas_response( 'cas_user!' );

test "login types include SSO",
   requires => [ $main::API_CLIENTS[0] ],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "GET",
         uri => "/r0/login",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( flows ));
         assert_json_list $body->{flows};

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
         method => "GET",
         uri => "/r0/login",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( flows ));
         assert_json_list $body->{flows};

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

      # the ticket our mocked-up CAS server "generates"
      my $CAS_TICKET = "goldenticket";

      # Ensure the base login works without issue.
      matrix_login_with_cas(
         '@cas_user=21:' . $http->server_name,
         $CAS_TICKET,
         $http,
         $homeserver_info,
         $CAS_SUCCESS,
      );
   };
