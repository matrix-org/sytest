use List::Util qw( first );


sub check_for_push_rules {
   my ( $sync_body ) = @_;

   my $account_data = $sync_body->{account_data}{events};

   my $push_rule_event = first { $_->{type} eq "m.push_rules" } @$account_data;

   assert_json_keys( $push_rule_event->{content}, qw( global ) );

   Future->done(1);
};


sub check_woken_up_by_push_rules {
   my ( $user, $action ) = @_;

   matrix_sync( $user )->then( sub {
      Future->needs_all(
         matrix_sync_again( $user,
            timeout => 10000 * $TIMEOUT_FACTOR,
            filter => '{"room":{"rooms":[]},"presence":{"types":[]}}',
         )->then( \&check_for_push_rules ),
         $action->(),
      );
   });
}

test "Push rules come down in an initial /sync",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_sync( $user )->then( \&check_for_push_rules );
   };

test "Adding a push rule wakes up an incremental /sync",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      check_woken_up_by_push_rules( $user, sub {
          matrix_add_push_rule( $user, "global", "room", "!foo:example.com",
            { actions => [ "notify" ] }
         )
      });
   };

test "Disabling a push rule wakes up an incremental /sync",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_add_push_rule( $user, "global", "room", "!foo:example.com",
         { actions => [ "notify" ] }
      )->then( sub {
         check_woken_up_by_push_rules( $user, sub {
            matrix_set_push_rule_enabled(
               $user,  "global", "room", "!foo:example.com", JSON::false
            );
         });
      });
   };

test "Enabling a push rule wakes up an incremental /sync",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_add_push_rule( $user, "global", "room", "!foo:example.com",
         { actions => [ "notify" ] }
      )->then( sub {
         matrix_set_push_rule_enabled(
            $user,  "global", "room", "!foo:example.com", JSON::false
         );
      })->then( sub {
         check_woken_up_by_push_rules( $user, sub {
            matrix_set_push_rule_enabled(
               $user,  "global", "room", "!foo:example.com", JSON::true
            );
         });
      });
   };

test "Setting actions for a push rule wakes up an incremental /sync",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_add_push_rule( $user, "global", "room", "!foo:example.com",
         { actions => [ "notify" ] }
      )->then( sub {
         check_woken_up_by_push_rules( $user, sub {
            matrix_set_push_rule_actions(
               $user,  "global", "room", "!foo:example.com", [ "dont_notify" ]
            )
         });
      });
   };
