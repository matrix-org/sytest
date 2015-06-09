test "AS can create a user",
   requires => [qw( do_request_json_for as_user )],

   do => sub {
      my ( $do_request_json_for, $as_user ) = @_;

      $do_request_json_for->( $as_user,
         method => "POST",
         uri    => "/register",

         content => {
            type => "m.login.application_service",
            user => "astest-01create-1",
         },
      )->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         require_json_keys( $body, qw( user_id home_server ));

         Future->done(1);
      });
   };

test "AS cannot create users outside its own namespace",
   requires => [qw( do_request_json_for as_user expect_http_4xx )],

   do => sub {
      my ( $do_request_json_for, $as_user, $expect_http_4xx ) = @_;

      $do_request_json_for->( $as_user,
         method => "POST",
         uri    => "/register",

         content => {
            type => "m.login.application_service",
            user => "a-different-user",
         }
      )->$expect_http_4xx;
   };

test "Regular users cannot register within the AS namespace",
   requires => [qw( register_new_user first_http_client expect_http_4xx )],

   do => sub {
      my ( $register_new_user, $http, $expect_http_4xx ) = @_;

      $register_new_user->( $http, "astest-01create-2" )
         ->$expect_http_4xx;
   };
