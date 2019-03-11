use utf8;

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
