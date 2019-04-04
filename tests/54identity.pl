test "Can bind 3PID via home server",
   requires => [ $main::HTTP_CLIENT, local_user_fixture(), id_server_fixture() ],

   check => sub {
      my ( $http, $user, $id_server ) = @_;

      my $medium = "email";
      my $address = 'bob@example.com';
      my $client_secret = "a client secret";

      my $sid = $id_server->validate_identity( $medium, $address, $client_secret );

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/account/3pid",
         content => {
            three_pid_creds => {
               id_server     => $id_server->name,
               sid           => $sid,
               client_secret => $client_secret,
            },
            bind => JSON::true,
         },
      )->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );

         assert_eq( $res, $user->user_id );

         Future->done( 1 );
      });
   };
