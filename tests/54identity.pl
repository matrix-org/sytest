sub bind_email_for_user {
   my ( $user, $address, $id_server, %params ) = @_;

   # Generate a client secret that is just numerics with `"Az.=_-"` on the end.
   my $client_secret = (join "", map { chr 48 + rand 10 } 1 .. 20) . "Az.=_-";

   my $id_access_token = $id_server->get_access_token();

   my $sid = $id_server->validate_identity( 'email', $address, $client_secret );

   do_request_json_for(
      $user,
      method => "POST",
      uri    => "/unstable/account/3pid/bind",
      content => {
         id_server       => $id_server->name,
         id_access_token => $id_access_token,
         sid             => $sid,
         client_secret   => $client_secret,
      },
   );
}


test "Can bind 3PID via home server",
   requires => [ $main::HTTP_CLIENT, local_user_fixture(), id_server_fixture() ],

   check => sub {
      my ( $http, $user, $id_server ) = @_;

      my $medium = "email";
      my $address = 'bob1@example.com';

      bind_email_for_user(
         $user, $address, $id_server,
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
      my $address = 'bob2@example.com';

      bind_email_for_user(
         $user, $address, $id_server,
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
      my $address = 'bob3@example.com';

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
      my $address = 'bob4@example.com';

      bind_email_for_user(
         $user, $address, $id_server,
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


test "Can bind and unbind 3PID via /unbind by specifying the identity server",
   requires => [ $main::HTTP_CLIENT, local_user_fixture(), id_server_fixture() ],

   check => sub {
      my ( $http, $user, $id_server ) = @_;

      my $medium = "email";
      my $address = 'bobby@example.com';

      bind_email_for_user(
         $user, $address, $id_server,
      )->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );
         assert_eq( $res, $user->user_id );

         do_request_json_for( $user,
            method => "POST",
            uri    => "/unstable/account/3pid/unbind",
            content => {
               id_server => $id_server->name,
               medium    => $medium,
               address   => $address,
            },
         )
      })->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );
         !defined $res or die "User 3PID still bound";

         Future->done( 1 );
      });
   };


test "Can bind and unbind 3PID via /unbind without specifying the identity server",
   requires => [ $main::HTTP_CLIENT, local_user_fixture(), id_server_fixture() ],

   check => sub {
      my ( $http, $user, $id_server ) = @_;

      my $medium = "email";
      my $address = 'bobby2@example.com';

      bind_email_for_user(
         $user, $address, $id_server,
      )->then( sub {
         my $res = $id_server->lookup_identity( $medium, $address );
         assert_eq( $res, $user->user_id );

         do_request_json_for( $user,
            method => "POST",
            uri    => "/unstable/account/3pid/unbind",
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
