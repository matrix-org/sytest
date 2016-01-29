my $password = "my secure password";


test "Can login with 3pid and password using m.login.password",
   requires => [ local_user_fixture( password => $password ), id_server_fixture() ],

   check => sub {
      my ( $user, $id_server) = @_;

      my $http = $user->http;

      my $medium = "email";
      my $address = 'bob@example.com';

      my $sid = $id_server->validate_identity( $medium, $address, "a client secret");

      do_request_json_for( $user,
         method => "POST",
         uri    => "/unstable/account/3pid",
         content => {
            three_pid_creds => {
               id_server     => $id_server->name,
               sid           => $sid,
               client_secret => "",
            },
            bind => JSON::false,
         },
      )->then( sub {
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/login",

            content => {
               type     => "m.login.password",
               medium   => $medium,
               address  => $address,
               password => $password,
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( access_token home_server ));

         assert_eq( $body->{home_server}, $http->server_name,
            'Response home_server' );

         Future->done(1);
      });
   };
