test "/whois",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      my $user;

      # Register a user, rather than using a fixture, because we want to very
      # tightly control the actions taken by that user.
      # Conceivably this API may change based on the number of API calls the
      # user made, for instance.
      matrix_register_user( $http, "admin" )
      ->then( sub {
         ( $user ) = @_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/admin/whois/".$user->user_id,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( devices user_id ) );
         assert_eq( $body->{user_id}, $user->user_id, "user_id" );
         assert_json_object( $body->{devices} );

         foreach my $value ( values %{ $body->{devices} } ) {
            assert_json_keys( $value, "sessions" );
            assert_json_list( $value->{sessions} );
            assert_json_keys( $value->{sessions}[0], "connections" );
            assert_json_list( $value->{sessions}[0]{connections} );
            assert_json_keys( $value->{sessions}[0]{connections}[0], qw( ip last_seen user_agent ) );
         }

         Future->done( 1 );
      });
   };
