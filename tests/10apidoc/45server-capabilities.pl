my $user_fixture = local_user_fixture();
test "GET /capabilities is present and well formed for registered user",
   requires => [ $main::API_CLIENTS[0], $user_fixture],
   do => sub {
         my ( $http, $user ) = @_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/capabilities",
         )->then( sub {
            my ( $body ) = @_;
            assert_json_keys( $body->{capabilities}, qw( m.room_versions m.change_password ));
            Future->done(1);
         });
      };


test "GET /r0/capabilities is not public",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "GET",
         uri    => "/r0/capabilities",
      )->main::expect_http_401->then( sub {
         Future->done( 1 );
      })
   };
