test "Can fetch a user's pushers",
   requires => [ local_user_fixture( ) ],

   check => sub {
      my ( $alice ) = @_;

      my $profile_tag = "tag";
      my $app_id = "sytest";
      my $app_display_name = "SyTest";
      my $device_display_name = "A testing machine";
      my $pushkey = "This is my pushkey";
      my $lang = "en";
      my $customdata = "This is some custom data";

      # create a pusher
      do_request_json_for( $alice,
         method  => "POST",
         uri     => "/r0/pushers/set",
         content => {
            profile_tag         => $profile_tag,
            kind                => "test",
            app_id              => $app_id,
            app_display_name    => $app_display_name,
            device_display_name => $device_display_name,
            pushkey             => $pushkey,
            lang                => $lang,
            data                => {
               testcustom => $customdata,
            },
         },
      )->then( sub {
         do_request_json_for( $alice,
            method  => "GET",
            uri     => "/r0/pushers",
         );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Get pusher response body", $body;

         assert_json_keys( my $notification = $body, qw(pushers));

         assert_json_keys( my $pusher = $body->{pushers}[0], qw(
            profile_tag kind app_id app_display_name device_display_name
            pushkey lang data
         ));
         assert_eq( $pusher->{profile_tag}, $profile_tag, "profile tag");
         assert_eq( $pusher->{app_id}, $app_id, "app id");
         assert_eq( $pusher->{app_display_name}, $app_display_name, "app_display_name");
         assert_eq( $pusher->{device_display_name}, $device_display_name, "device_display_name");
         assert_eq( $pusher->{pushkey}, $pushkey, "pushkey");
         assert_eq( $pusher->{lang}, $lang, "lang");
         assert_eq( $pusher->{data}{testcustom}, $customdata, "custom data");

         Future->done(1);
      });
   };
