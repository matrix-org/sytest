my $password = "my secure password";

test "Can login with 3pid and password using m.login.password",
   requires => [ local_user_fixture( password => $password ), id_server_fixture() ],

   check => sub {
      my ( $user, $id_server ) = @_;

      my $http = $user->http;

      my $address = 'bob@example.com';

      add_email_for_user( $user, $address, $id_server )
      ->then( sub {
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/login",

            content => {
               type     => "m.login.password",
               medium   => 'email',
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
