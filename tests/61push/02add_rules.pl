use utf8;

use List::Util qw( first );

sub check_add_push_rule
{
   my ( $user, $scope, $kind, $rule_id, $rule_body, %params ) = @_;

   my $check_rule = sub {
      my ( $rule ) = @_;

      log_if_fail "Rule", $rule;

      assert_json_keys( $rule, qw( rule_id actions enabled ) );

      assert_json_boolean( $rule->{enabled} );

      assert_eq( $rule->{rule_id}, $rule_id );
   };

   my $check_rule_list = sub {
      my ( $rules ) = @_;

      my ( $rule ) = first { $_->{rule_id} eq $rule_id } @$rules;

      $check_rule->( $rule );
   };

   matrix_add_push_rule( $user, $scope, $kind, $rule_id, $rule_body, %params )
   ->then( sub {
      matrix_get_push_rule( $user, $scope, $kind, $rule_id )
      ->on_done( $check_rule );
   })->then( sub {
      # Trailing slash indicates retrieving ALL push rules for this scope/kind
      do_request_json_for( $user,
         method  => "GET",
         uri     => "/r0/pushrules/$scope/$kind/",
      )->on_done( $check_rule_list );
   })->then( sub {
      # Trailing slash indicates retrieving ALL push rules for this scope
       do_request_json_for( $user,
         method  => "GET",
         uri     => "/r0/pushrules/$scope/",
      )->on_done( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, $kind );
         $check_rule_list->( $body->{$kind} );
      });
   })->then( sub {
      matrix_get_push_rules( $user )->on_done( sub {
         my ( $body ) = @_;

         assert_json_keys( $body->{$scope}, $kind );
         $check_rule_list->( $body->{$scope}{$kind} );
      });
   })->then( sub {
      # Check that the rule is enabled.
      do_request_json_for( $user,
         method  => "GET",
         uri     => "/r0/pushrules/$scope/$kind/$rule_id/enabled",
      )->on_done( sub {
         my ( $body ) = @_;

         assert_deeply_eq( $body, { enabled => JSON::true } );
      });
   })->then( sub {
      # Check that the actions match.
      do_request_json_for( $user,
         method  => "GET",
         uri     => "/r0/pushrules/$scope/$kind/$rule_id/actions",
      )->on_done( sub {
         my ( $body ) = @_;

         assert_deeply_eq( $body, { actions => $rule_body->{actions} } );
      });
   })
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
   [ "content", "тест", { pattern => "тест" } ],
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
         actions => [ "notify" ],
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#b:example.com", {
            actions => [ "notify" ],
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

   check => sub {
      my ( $user ) = @_;

      check_add_push_rule( $user, "global", "room", "#a:example.com", {
         actions => [ "notify" ],
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#b:example.com", {
            actions => [ "notify" ],
         });
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#c:example.com", {
            actions => [ "notify" ],
         }, before => "#a:example.com" );
      })->then( sub {
         matrix_get_push_rules( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( my $global = $body->{global}, qw( room ) );
         assert_json_list( my $room = $global->{room} );

         log_if_fail "Room rules", $room;

         assert_eq( $room->[0]{rule_id}, "#b:example.com" );
         assert_eq( $room->[1]{rule_id}, "#c:example.com" );
         assert_eq( $room->[2]{rule_id}, "#a:example.com" );

         Future->done(1);
      });
   };


test "Can add global push rule after an existing rule",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      check_add_push_rule( $user, "global", "room", "#a:example.com", {
         actions => [ "notify" ],
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#b:example.com", {
            actions => [ "notify" ],
         });
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#c:example.com", {
            actions => [ "notify" ],
         }, after => "#b:example.com" );
      })->then( sub {
         matrix_get_push_rules( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( my $global = $body->{global}, qw( room ) );
         assert_json_list( my $room = $global->{room} );

         log_if_fail "Room rules", $room;

         assert_eq( $room->[0]{rule_id}, "#b:example.com" );
         assert_eq( $room->[1]{rule_id}, "#c:example.com" );
         assert_eq( $room->[2]{rule_id}, "#a:example.com" );

         Future->done(1);
      });
   };


test "Can delete a push rule",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      check_add_push_rule( $user, "global", "room", "#a:example.com", {
         actions => [ "notify" ],
      })->then( sub {
         check_add_push_rule( $user, "global", "room", "#b:example.com", {
            actions => [ "notify" ],
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


test "Can disable a push rule",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      check_add_push_rule( $user, "global", "room", "#a:example.com", {
         actions => [ "notify" ],
      })->then( sub {
         matrix_set_push_rule_enabled( $user, "global", "room", "#a:example.com", JSON::false );
      })->then( sub {
         matrix_get_push_rule( $user, "global", "room", "#a:example.com" );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( enabled ));
         assert_eq( $body->{enabled}, JSON::false, "enabled" );

         Future->done(1);
      });
   };


test "Adding the same push rule twice is idempotent",
   requires => [ local_user_fixture() ],

   do => sub {
      my ( $user ) = @_;

      matrix_add_push_rule( $user, "global", "sender", '@bob:example.com', {
         actions => [ "notify" ]
      })->then( sub {
         matrix_add_push_rule( $user, "global", "sender", '@bob:example.com', {
            actions => [ "notify" ]
         });
      })->then( sub {
         matrix_get_push_rules( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( my $global = $body->{global}, qw( sender ) );
         assert_json_list( my $sender = $global->{sender} );

         assert_eq( $sender->[0]{rule_id}, '@bob:example.com' );

         @$sender == 1 or die "Expected only one rule";

         Future->done(1);
      });
   };
