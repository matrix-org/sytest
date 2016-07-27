test "User signups are forbidden from starting with '_'",
   requires => [ $main::API_CLIENTS[0] ],

   bug => "SYN-738",

   do => sub {
      my ( $http ) = @_;

      matrix_register_user( $http, "_badname_here" )
         ->main::expect_http_4xx;
   };

test "AS can create users starting with '_'",
   requires => [ $main::AS_USER[0] ],

   do => sub {
      my ( $as_user ) = @_;

      do_request_json_for( $as_user,
         method => "POST",
         uri    => "/api/v1/register",

         content => {
            type => "m.login.application_service",
            user => "_astest-goes-here",
         },
      );
   };
