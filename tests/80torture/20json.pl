# Test integers that are outside of the range of [-2 ^ 53 + 1, 2 ^ 53 - 1].
test "Invalid JSON integers",
   requires => [ local_user_and_room_fixtures(
      room_opts => { room_version => "6" }
   ), ],

   do => sub {
      my ( $user, $room_id ) = @_;

      Future->needs_all(
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/rooms/$room_id/send/sytest.dummy",
            content => {
               msgtype => "sytest.dummy",
               body    => 9007199254740992,  # 2 ** 53
            },
         )->followed_by( \&main::expect_http_400 ),

         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/rooms/$room_id/send/sytest.dummy",
            content => {
               msgtype => "sytest.dummy",
               body    => -9007199254740992,  # -2 ** 53
            },
         )->followed_by( \&main::expect_http_400 ),
      );
   };

# Floats should be rejected.
test "Invalid JSON floats",
   requires => [ local_user_and_room_fixtures(
      room_opts => { room_version => "6" }
   ), ],

   do => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method  => "POST",
         uri     => "/r0/rooms/$room_id/send/sytest.dummy",
         content => {
            msgtype => "sytest.dummy",
            body    => 1.1,
         },
      )->followed_by( \&main::expect_http_400 );
   };

# Special values (like inf/nan) should be rejected. Note that these values are
# not technically valid JSON, but extensions that some programming languages
# support automatically.
test "Invalid JSON special values",
   requires => [ local_user_and_room_fixtures(
      room_opts => { room_version => "6" }
   ), ],

   do => sub {
      my ( $user, $room_id ) = @_;

      my $http = $user->http;

      Future->needs_all(
         # Try some Perl magic values.
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/rooms/$room_id/send/sytest.dummy",
            content => {
               msgtype => "sytest.dummy",
               body    => "NaN" + 0,
            },
         )->followed_by( \&main::expect_http_400 ),

         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/rooms/$room_id/send/sytest.dummy",
            content => {
               msgtype => "sytest.dummy",
               body    => "inf" + 0,
            },
         )->followed_by( \&main::expect_http_400 ),

         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/rooms/$room_id/send/sytest.dummy",
            content => {
               msgtype => "sytest.dummy",
               body    => "-inf" + 0,
            },
         )->followed_by( \&main::expect_http_400 ),

         # Try some Python magic values.
         $user->http->do_request(
            method       => "POST",
            uri          => "/r0/rooms/$room_id/send/sytest.dummy",
            params       => {
               access_token => $user->access_token,
            },
            content      => '{"msgtype": "sytest.dummy", "body": Infinity}',
            content_type => "application/json",
         )->followed_by( \&main::expect_http_400 ),

         $user->http->do_request(
            method       => "POST",
            uri          => "/r0/rooms/$room_id/send/sytest.dummy",
            params       => {
               access_token => $user->access_token,
            },
            content      => '{"msgtype": "sytest.dummy", "body": -Infinity}',
            content_type => "application/json",
         )->followed_by( \&main::expect_http_400 ),

         $user->http->do_request(
            method       => "POST",
            uri          => "/r0/rooms/$room_id/send/sytest.dummy",
            params       => {
               access_token => $user->access_token,
            },
            content      => '{"msgtype": "sytest.dummy", "body": NaN}',
            content_type => "application/json",
         )->followed_by( \&main::expect_http_400 ),
      );
   };
