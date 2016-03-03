
my $TO_CHECK_PUT = [
   [ "no scope", "/", {} ],
   [ "invalid scope", "/not_a_scope/room/#spam:example.com", {} ],
   [ "missing template", "/global", {} ],
   [ "missing rule_id", "/global/room", {} ],
   [ "empty rule_id", "/global/room/", {} ],
   [ "invalid template", "/global/not_a_template/foo", {} ],
   [ "rule_id with slashes", "/global/room/#fo\\o:example.com", {} ],
   [ "override rule without conditions", "/global/override/my_id", {} ],
   [ "underride rule without conditions", "/global/underride/my_id", {} ],
   [ "condition without kind", "/global/underride/my_id", {
      conditions => [ {} ]
   }],
   [ "content rule without pattern", "/global/content/my_id", {} ],
   [ "no actions", "/global/room/#my_room:example.com", {} ],
   [ "invalid action", "/global/room/#my_room:example.com", {
      actions => ["not_an_action"]
   }],
   [ "invalid attr", "/global/override/.m.rule.master/not_an_attr", {
      enabled => JSON::true,
   }],
   [ "invalid value for enabled", "/global/override/.m.rule.master/enabled", {
      enabled => "not a boolean"
   }],
];

foreach my $test_put ( @$TO_CHECK_PUT ) {
   my ( $name, $path, $rule ) = @$test_put;

   test "Trying to add push rule with $name fails with 400",
      requires => [ local_user_fixture() ],

      check => sub {
         my ( $user ) = @_;

         do_request_json_for( $user,
            method  => "PUT",
            uri     => "/r0/pushrules$path",
            content => $rule,
         )->main::expect_http_400;
      };
};

my $TO_CHECK_GET_400 = [
   [ "no trailing slash", "" ],
   [ "scope without trailing slash", "/global" ],
   [ "template without tailing slash", "/global/room" ],
   [ "unknown scope", "/not_a_scope/" ],
   [ "unknown template", "/global/not_a_template/" ],
   [ "unknown attribute", "/global/override/.m.rule.master/not_an_attr"],
];

foreach my $test_get ( @$TO_CHECK_GET_400 ) {
   my ( $name, $path ) = @$test_get;

   test "Trying to get push rules with $name fails with 400",
      requires => [ local_user_fixture() ],

      check => sub {
         my ( $user ) = @_;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/r0/pushrules$path",
         )->main::expect_http_400;
      };
};

my $TO_CHECK_GET_404 = [
   [ "unknown rule_id", "/global/override/not_a_rule_id" ],
];

foreach my $test_get ( @$TO_CHECK_GET_404 ) {
   my ( $name, $path ) = @$test_get;

   test "Trying to get push rules with $name fails with 404",
      requires => [ local_user_fixture() ],

      check => sub {
         my ( $user ) = @_;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/r0/pushrules$path",
         )->main::expect_http_404;
      };
};
