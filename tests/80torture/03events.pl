test "GET /initialSync with non-numeric 'limit'",
   requires => [ our $SPYGLASS_USER,
                 qw( can_initial_sync )],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/initialSync",

         params => { limit => "hello" },
      )->main::expect_http_4xx;
   };

test "GET /events with non-numeric 'limit'",
   requires => [ $SPYGLASS_USER ],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/events",

         params => { from => $user->eventstream_token, limit => "hello" },
      )->main::expect_http_4xx;
   };

test "GET /events with negative 'limit'",
   requires => [ $SPYGLASS_USER ],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/events",

         params => { from => $user->eventstream_token, limit => -2 },
      )->main::expect_http_4xx;
   };

test "GET /events with non-numeric 'timeout'",
   requires => [ $SPYGLASS_USER ],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/events",

         params => { from => $user->eventstream_token, timeout => "hello" },
      )->main::expect_http_4xx;
   };
