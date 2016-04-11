use Future::Utils qw( repeat );

sub check_change_enabled {
   my ( $user, $scope, $kind, $rule_id, $enabled ) = @_;

   matrix_set_push_rule_enabled( $user, $scope, $kind, $rule_id, $enabled )
   ->then( sub {
      # Check that the actions match.
      do_request_json_for( $user,
         method  => "GET",
         uri     => "/r0/pushrules/$scope/$kind/$rule_id/enabled",
      )->on_done( sub {
         my ( $body ) = @_;

         assert_deeply_eq( $body, { enabled => $enabled } );
      });
   });
}

sub check_enable_disable_rule {
   my ( $user, $scope, $kind, $rule_id ) = @_;

   check_change_enabled( $user, $scope, $kind, $rule_id, JSON::true )
   ->then( sub {
      check_change_enabled( $user, $scope, $kind, $rule_id, JSON::false );
   })->then( sub {
      check_change_enabled( $user, $scope, $kind, $rule_id, JSON::true );
   });
}

test "Can enable/disable default rules",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

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

            check_enable_disable_rule( $user, "global", $kind, $rule_id);
         } foreach => \@to_check;
      });
   };

test "Enabling an unknown default rule fails with 404",
   requires => [ local_user_fixture() ],

   bug => "SYN-?",

   check => sub  {
      my ( $user ) = @_;
      matrix_set_push_rule_enabled(
         $user, "global", "override", ".not.a.default.rule", JSON::true
      )->main::expect_http_404;
   };
