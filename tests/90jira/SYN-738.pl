test "User signups are forbidden from starting with '_'",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      matrix_register_user( $http, "_badname_here" )
         ->main::expect_http_4xx;
   };
