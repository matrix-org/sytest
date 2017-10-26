test "AS can deactivate a user",
   requires => [ $main::AS_USER[0], as_ghost_fixture() ],

   do => sub {
      my ( $as_user, $ghost ) = @_;

      do_request_json_for(
         $as_user,
         method  => "POST",
         uri     => "/r0/account/deactivate",
         params  => { user_id => $ghost->user_id },
         content => {},
      );
   };
