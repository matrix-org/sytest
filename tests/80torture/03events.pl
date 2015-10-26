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

test "Event size limits",
   requires => do {
      my $user = local_user_preparer();
      [ $user, room_preparer( requires_users => [ $user ] ) ];
   },

   do => sub {
      my ( $user, $room_id ) = @_;

      Future->needs_all(
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/send/m.room.message",
            content => {
               msgtype => "m.text",
               body    => "A" x 70000,
            },
         )->followed_by( \&main::expect_http_413 ),

         do_request_json_for( $user,
            method  => "PUT",
            uri     => "/api/v1/rooms/$room_id/state/oooooooh/",
            content => {
               key => "O" x 70000,
            }
         )->followed_by( \&main::expect_http_413 ),
      );
   };
