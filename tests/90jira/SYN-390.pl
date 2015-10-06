multi_test "Getting push rules doesn't corrupt the cache SYN-390",
   prepare => local_user_preparer(),

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method  => "PUT",
         uri     => "/api/v1/pushrules/global/sender/%40a_user%3Amatrix.org",
         content => { "actions" => ["dont_notify"] }
      )->SyTest::pass_on_done("Set push rules for user" )
      ->then( sub {

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/pushrules/",
         )->SyTest::pass_on_done("Got push rules the first time" )
      })->then( sub {

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/pushrules/",
         )->SyTest::pass_on_done("Got push rules the second time" )
      })->then_done(1);
   }
