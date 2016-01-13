use Future::Utils qw( repeat );

push our @EXPORT, qw(
   matrix_add_push_rule matrix_delete_push_rule
   matrix_get_push_rule matrix_get_push_rules
);

=head2 matrix_add_push_rule

   matrix_add_push_rule( $user, $scope, $kind, $rule_id, $rule, %params )->get

scope: Either "global" or "device/<profile_tag>"
kind: Either "override", "underride", "sender", "room", or "content"
rule_id: String id for the rule.
rule: Hash reference for the body.
params: Extra query params for the request. E.g. "before" or "after".

=cut

sub matrix_add_push_rule
{
   my ( $user, $scope, $kind, $rule_id, $rule_body, %params ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/pushrules/$scope/$kind/$rule_id",
      params  => \%params,
      content => $rule_body,
   );
}

=head2 matrix_delete_push_rule

   matrix_delete_push_rule( $user, $scope, $kind, $rule_id )->get

scope: Either "global" or "device/<profile_tag>"
kind: Either "override", "underride", "sender", "room", or "content"
rule_id: String id for the rule.

=cut

sub matrix_delete_push_rule
{
   my ( $user, $scope, $kind, $rule_id ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/r0/pushrules/$scope/$kind/$rule_id",
   );
}

=head2 matrix_get_push_rule

   my $rule = matrix_get_push_rule( $user, $scope, $kind, $rule_id )->get

scope: Either "global" or "device/<profile_tag>"
kind: Either "override", "underride", "sender", "room", or "content"
rule_id: String id for the rule.

Returns a hash reference with the rule body.

=cut

sub matrix_get_push_rule
{
   my ( $user, $scope, $kind, $rule_id ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/r0/pushrules/$scope/$kind/$rule_id",
   );
}

=head2 matrix_get_push_rules

   my $rules = matrix_get_push_rules( $user )->get

Returns a hash reference with all the rules for the user

=cut

sub matrix_get_push_rules
{
   my ( $user ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/r0/pushrules/",
   )->on_done( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, qw( global device ) );
   });
}

sub check_add_push_rule
{
   my ( $user, $scope, $kind, $rule_id, $rule_body, %params ) = @_;

   matrix_add_push_rule( $user, $scope, $kind, $rule_id, $rule_body, %params )
   ->then( sub {
      matrix_get_push_rule( $user, $scope, $kind, $rule_id );
   })->then( sub {
      my ( $rule ) = @_;

      log_if_fail "Rule", $rule;

      assert_json_keys( $rule, qw( rule_id actions enabled ) );

      assert_eq( $rule->{rule_id}, $rule_id );

      Future->done(1);
   });
}


my $TO_CHECK = [
   [ "room", "#spam:example.com", {} ],
   [ "sender", "\@bob:example.com", {} ],
   [ "content", "my_content_rule", { pattern => "my_pattern" } ],
   [ "override", "my_override_rule", { conditions => [ {
      kind => "event_match",
      key => "content.msgtype",
      pattern => "m.notice",
   }]}],
   [ "underride", "my_underride_rule", { conditions => [ {
      kind => "event_match",
      key => "content.msgtype",
      pattern => "m.notice",
   }]}],
];

foreach my $test ( @$TO_CHECK ) {
   my ( $kind, $rule_id, $rule ) = @$test;

   test "Can add global push rule for $kind",
      requires => [ local_user_fixture() ],

      check => sub {
         my ( $user ) = @_;

         check_add_push_rule( $user, "global", $kind, $rule_id, {
            actions => [ "notify" ], %$rule
         });
      };
};


test "New rules appear before old rules by default",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      check_add_push_rule( $user, "global", "room", "#a:example.com", {
         actions => ["notify"],
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#b:example.com", {
            actions => ["notify"],
         });
      })->then( sub {
         matrix_get_push_rules( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( my $global = $body->{global}, qw( room ) );
         assert_json_list( my $room = $global->{room} );

         assert_eq( $room->[0]{rule_id}, "#b:example.com" );
         assert_eq( $room->[1]{rule_id}, "#a:example.com" );

         Future->done(1);
      });
   };


test "Can add global push rule before an existing rule",
   requires => [ local_user_fixture() ],

   bug => "SYN-591",

   check => sub {
      my ( $user ) = @_;

      check_add_push_rule( $user, "global", "room", "#a:example.com", {
            actions => ["notify"],
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#b:example.com", {
            actions => ["notify"],
         }, before => "#a:example.com" );
      })->then( sub {
         matrix_get_push_rules( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( my $global = $body->{global}, qw( room ) );
         assert_json_list( my $room = $global->{room} );

         assert_eq( $room->[0]{rule_id}, "#b:example.com" );
         assert_eq( $room->[1]{rule_id}, "#a:example.com" );

         Future->done(1);
      });
   };


test "Can add global push rule after an existing rule",
   requires => [ local_user_fixture() ],

   bug => "SYN-592",

   check => sub {
      my ( $user ) = @_;

      check_add_push_rule( $user, "global", "room", "#a:example.com", {
         actions => ["notify"],
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#b:example.com", {
            actions => ["notify"],
         });
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#c:example.com", {
            actions => ["notify"],
         }, after => "#a:example.com" );
      })->then( sub {
         matrix_get_push_rules( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( my $global = $body->{global}, qw( room ) );
         assert_json_list( my $room = $global->{room} );

         assert_eq( $room->[0]{rule_id}, "#a:example.com" );
         assert_eq( $room->[1]{rule_id}, "#c:example.com" );
         assert_eq( $room->[2]{rule_id}, "#b:example.com" );

         Future->done(1);
      });
   };


test "Can delete a push rule",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      check_add_push_rule( $user, "global", "room", "#a:example.com", {
         actions => ["notify"],
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#b:example.com", {
            actions => ["notify"],
         });
      })->then( sub {
         matrix_delete_push_rule( $user, "global", "room", "#a:example.com");
      })->then( sub {
         matrix_get_push_rules( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( my $global = $body->{global}, qw( room ) );
         assert_json_list( my $room = $global->{room} );

         assert_eq( $room->[0]{rule_id}, "#b:example.com" );

         Future->done(1);
      });
   };

