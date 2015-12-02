test "/whois",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      my $user;

      matrix_register_user( $http )
      ->then( sub {
         ( $user ) = @_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/admin/whois/".$user->user_id,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, "devices", "user_id" );
         assert_eq( $body->{user_id}, $user->user_id, "user_id" );
         assert_json_list( $body->{devices} );
         assert_json_keys( $body->{devices}[0], "sessions" );
         assert_json_list( $body->{devices}[0]{sessions} );
         assert_json_keys( $body->{devices}[0]{sessions}[0], "connections" );
         assert_json_list( $body->{devices}[0]{sessions}[0]{connections} );
         assert_json_keys( $body->{devices}[0]{sessions}[0]{connections}[0], "ip", "last_seen", "user_agent" );

         Future->done( 1 );
      });
   };
