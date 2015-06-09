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
