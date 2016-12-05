sub default_global_rules
{
   my ( $user_id ) = @_;

   my ( $user_localpart ) = ( $user_id =~ m/@([^:]*):/ );

   # Taken from https://matrix.org/speculator/spec/HEAD/client_server/unstable.html#predefined-rules

   return {
      override => [
         {
            actions    => [
               "dont_notify",
            ],
            conditions => [],
            default    => JSON::true,
            enabled    => JSON::false,
            rule_id    => ".m.rule.master",
         },
         {
            actions    => [
               "dont_notify",
            ],
            conditions => [
               {
                  key      => "content.msgtype",
                  kind     => "event_match",
                  pattern  => "m.notice",
               },
            ],
            default    => JSON::true,
            enabled    => JSON::true,
            rule_id    => ".m.rule.suppress_notices",
         },
         {
            actions    => [
                "notify",
                { set_tweak => "sound", value => "default" },
                { set_tweak => "highlight", value => JSON::false },
            ],
            conditions => [
               { key => "type", kind => "event_match", pattern => "m.room.member" },
               { key => "content.membership", kind => "event_match", pattern => "invite" },
               {
                  key => "state_key",
                  kind => "event_match",
                  pattern => "$user_id",
               },
            ],
            default    => JSON::true,
            enabled    => JSON::true,
            rule_id    => ".m.rule.invite_for_me",
         },
         {
            actions    => ["dont_notify"],
            conditions => [
               { key => "type", kind => "event_match", pattern => "m.room.member" },
            ],
            default    => JSON::true,
            enabled    => JSON::true,
            rule_id    => ".m.rule.member_event",
         },
      ],
      room => [],
      sender => [],
      content  => [
         {
            actions    => [
               "notify",
               {
                  set_tweak => "sound",
                  value     => "default"
               },
               {
                  set_tweak => "highlight"
               },
            ],
            default    => JSON::true,
            enabled    => JSON::true,
            pattern    => $user_localpart,
            rule_id    => ".m.rule.contains_user_name",
         }
      ],
      underride => [
         {
            actions    => [
               "notify",
               {
                  set_tweak => "sound",
                  value     => "ring",
               },
               {
                  set_tweak => "highlight",
                  value     => JSON::false,
               },
            ],
            conditions => [
               {
                  kind      => "event_match",
                  key       => "type",
                  pattern   => "m.call.invite"
               },
            ],
            default    => JSON::true,
            enabled    => JSON::true,
            rule_id    => ".m.rule.call",
         },
         {
            actions    => [
               "notify",
               {
                  set_tweak => "sound",
                  value     => "default",
               },
               {
                  set_tweak => "highlight",
               },
            ],
            conditions => [
               {
                  kind      => "contains_display_name",
               }
            ],
            default    => JSON::true,
            enabled    => JSON::true,
            rule_id    => ".m.rule.contains_display_name",
         },
         {
            actions    => [
               "notify",
               {
                  set_tweak => "sound",
                  value     => "default",
               },
               {
                  set_tweak => "highlight",
                  value     => JSON::false,
               },
            ],
            conditions => [
               {
                  kind     => "room_member_count",
                  is       => 2,
               },
               {
                  kind     => "event_match",
                  key      => "type",
                  pattern  => "m.room.message",
               },
            ],
            default    => JSON::true,
            enabled    => JSON::true,
            rule_id    => ".m.rule.room_one_to_one",
         },
         {
            actions    => [
               "notify",
               {
                  set_tweak => "highlight",
                  value     => JSON::false,
               }
            ],
            conditions => [
               {
                  kind      => "event_match",
                  key       => "type",
                  pattern   => "m.room.message",
               },
            ],
            default    => JSON::true,
            enabled    => JSON::true,
            rule_id    => ".m.rule.message",
         },
      ],
   }
}


test "The predefined push rules are correct for a new user",
   requires => [ local_user_fixture() ],

   do => sub {
      my ( $user ) = @_;

      matrix_get_push_rules( $user )->then( sub {
         my ( $body ) = @_;

         log_if_fail "Rules", $body;

         my $expected_rules = default_global_rules( $user->user_id );

         assert_deeply_eq( $body->{global}, $expected_rules );
         assert_deeply_eq( $body->{device}, {} );

         Future->done(1);
      });
   };


test "Adding a rule after a default rule fails with a 400",

   requires => [ local_user_fixture() ],

   do => sub {
       my ( $user ) = @_;

      matrix_add_push_rule( $user, "global", "underride", "my_underride_rule",
         {
            conditions => [],
            actions    => [ "notify" ]
         },
         after => ".m.rule.message"
      )->main::expect_http_400;
   };


test "Adding a rule before a default rule fails with a 400",

   requires => [ local_user_fixture() ],

   do => sub {
       my ( $user ) = @_;

      matrix_add_push_rule( $user, "global", "underride", "my_underride_rule",
         {
            conditions => [],
            actions    => [ "notify" ]
         },
         before => ".m.rule.message"
      )->main::expect_http_400;
   };
