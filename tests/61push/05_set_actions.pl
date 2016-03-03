use Future::Utils qw( repeat );

sub check_change_action {
   my ( $user, $scope, $kind, $rule_id, $actions ) = @_;

   matrix_set_push_rule_actions( $user, $scope, $kind, $rule_id, $actions )
   ->then( sub {
      # Check that the actions match.
      do_request_json_for( $user,
         method  => "GET",
         uri     => "/r0/pushrules/$scope/$kind/$rule_id/actions",
      )->on_done( sub {
         my ( $body ) = @_;

         assert_deeply_eq( $body, { actions => $actions } );
      });
   });
}

test "Can change the actions of default rules",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      my $actions = [ "dont_notify" ];

      matrix_get_push_rules( $user )->then( sub {
         my ( $body ) = @_;

         my @to_check;

         foreach my $kind ( keys %{ $body->{global} } ) {
            foreach my $rule ( @{ $body->{global}{$kind} } ) {
               push @to_check, [ $kind, $rule->{rule_id} ];
            }
         }

         repeat {
            my $to_check = shift;

            my ( $kind, $rule_id ) = @$to_check;

            check_change_action( $user, "global", $kind, $rule_id, $actions );
         } foreach => \@to_check;
      });
   };


test "Changing the actions of an unknown default rule fails with 404",
   requires => [ local_user_fixture() ],

   check => sub  {
      my ( $user ) = @_;
      matrix_set_push_rule_actions(
         $user, "global", "override", ".not.a.default.rule", [
            "notify"
         ],
      )->main::expect_http_404;
   };


test "Can change the actions of a user specified rule",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_add_push_rule( $user, "global", "sender", '@bob:example.com', {
         actions => [ "notify" ]
      })->then( sub {
         check_change_action( $user, "global", "sender", '@bob:example.com', [
            "dont_notify",
         ]);
      });
   };


test "Changing the actions of an unknown rule fails with 404",
   requires => [ local_user_fixture() ],

   check => sub  {
      my ( $user ) = @_;
      matrix_set_push_rule_actions(
         $user, "global", "sender", '@bob:example.com', [ "notify" ]
      )->main::expect_http_404;
   };

