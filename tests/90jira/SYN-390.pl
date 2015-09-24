multi_test "Getting push rules doesn't corrupt the cache SYN-390",
   requires => [qw( register_new_user api_clients do_request_json_for )],

   do => sub {
      my ( $register_new_user, $clients, $do_request_json_for ) = @_;
      my $http = $clients->[0];

      my $alice;

      $register_new_user->( $http, "90jira-SYN-390_alice" )->then( sub {
         ( $alice ) = @_;

         $do_request_json_for->( $alice,
            method  => "PUT",
            uri     => "/api/v1/pushrules/global/sender/%40a_user%3Amatrix.org",
            content => { "actions" => ["dont_notify"] }
         )->SyTest::pass_on_done("Set push rules for alice" )
      })->then( sub {

         $do_request_json_for->( $alice,
            method => "GET",
            uri    => "/api/v1/pushrules/",
         )->SyTest::pass_on_done("Got push rules the first time" )
      })->then( sub {

         $do_request_json_for->( $alice,
            method => "GET",
            uri    => "/api/v1/pushrules/",
         )->SyTest::pass_on_done("Got push rules the second time" )
      })->then_done(1);
   }
