test "GET /initialSync with non-numeric 'limit'",
   requires => [qw( do_request_json expect_http_4xx
                    can_initial_sync )],

   check => sub {
      my ( $do_request_json, $expect_http_4xx ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/initialSync",

         params => { limit => "hello" },
      )->$expect_http_4xx;
   };

test "GET /events with non-numeric 'limit'",
   requires => [qw( do_request_json_for user expect_http_4xx
                    can_get_events )],

   check => sub {
      my ( $do_request_json_for, $user, $expect_http_4xx ) = @_;

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/events",

         params => { from => $user->eventstream_token, limit => "hello" },
      )->$expect_http_4xx;
   };

test "GET /events with non-numeric 'timeout'",
   requires => [qw( do_request_json_for user expect_http_4xx
                    can_get_events )],

   check => sub {
      my ( $do_request_json_for, $user, $expect_http_4xx ) = @_;

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/events",

         params => { from => $user->eventstream_token, timeout => "hello" },
      )->$expect_http_4xx;
   };
