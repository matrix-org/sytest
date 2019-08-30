test "Can bind 3PID via home server",
   requires => [ $main::HTTP_CLIENT, local_user_fixture(), id_server_fixture() ],

   check => sub {
      my ( $http, $user, $id_server ) = @_;

      my $medium = "email";
      my $address = 'bob@example.com';
      my $client_secret = "a client secret";
      my $id_access_token = "testing";

      my $sid = $id_server->validate_identity( $medium, $address, $client_secret );

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/account/3pid",
         content => {
            three_pid_creds => {
               id_server       => $id_server->name,
               id_access_token => $id_access_token,
               sid             => $sid,
               client_secret   => $client_secret,
            },
            bind => JSON::true,
         },
      )->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );

         assert_eq( $res, $user->user_id );

         Future->done( 1 );
      });
   };


test "Can bind and unbind 3PID via homeserver",
   requires => [ $main::HTTP_CLIENT, local_user_fixture(), id_server_fixture() ],

   check => sub {
      my ( $http, $user, $id_server ) = @_;

      my $medium = "email";
      my $address = 'bob@example.com';
      my $client_secret = "a client secret";
      my $id_access_token = "testing";

      my $sid = $id_server->validate_identity( $medium, $address, $client_secret );

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/account/3pid",
         content => {
            three_pid_creds => {
               id_server       => $id_server->name,
               id_access_token => $id_access_token,
               sid             => $sid,
               client_secret   => $client_secret,
            },
            bind => JSON::true,
         },
      )->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );
         assert_eq( $res, $user->user_id );

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/account/3pid/delete",
            content => {
               medium  => $medium,
               address => $address,
            },
         )
      })->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );
         !defined $res or die "User 3PID still bound";

         Future->done( 1 );
      });
   };


test "Can unbind 3PID via homeserver when bound out of band",
   requires => [ $main::HTTP_CLIENT, local_user_fixture(), id_server_fixture() ],

   check => sub {
      my ( $http, $user, $id_server ) = @_;

      my $medium = "email";
      my $address = 'bob@example.com';

      # Bind the 3PID out of band of the homeserver
      $id_server->bind_identity( undef, $medium, $address, $user->user_id );
      my $res = $id_server->lookup_identity( $medium, $address );
      assert_eq( $res, $user->user_id );

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/account/3pid/delete",
         content => {
            medium    => $medium,
            address   => $address,
            id_server => $id_server->name,
         },
      )->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );
         !defined $res or die "User 3PID still bound";

         Future->done( 1 );
      });
   };


test "3PIDs are unbound after account deactivation",
   requires => [ $main::HTTP_CLIENT, local_user_fixture(), id_server_fixture() ],

   check => sub {
      my ( $http, $user, $id_server ) = @_;

      my $medium = "email";
      my $address = 'bob@example.com';
      my $client_secret = "a client secret";
      my $id_access_token = "testing";

      my $sid = $id_server->validate_identity( $medium, $address, $client_secret );

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/account/3pid",
         content => {
            three_pid_creds => {
               id_server       => $id_server->name,
               id_access_token => $id_access_token,
               sid             => $sid,
               client_secret   => $client_secret,
            },
            bind => JSON::true,
         },
      )->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );
         assert_eq( $res, $user->user_id );

         matrix_deactivate_account( $user )
      })->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );
         !defined $res or die "User 3PID still bound";

         Future->done( 1 );
      });
   };
