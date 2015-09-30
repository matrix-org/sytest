test "AS can create a user",
   requires => [qw( as_user )],

   provides => [qw( make_as_user )],

   do => sub {
      my ( $as_user ) = @_;

      do_request_json_for( $as_user,
         method => "POST",
         uri    => "/api/v1/register",

         content => {
            type => "m.login.application_service",
            user => "astest-01create-1",
         },
      )->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         require_json_keys( $body, qw( user_id home_server ));

         provide make_as_user => sub {
            my ( $user_id_fragment ) = @_;

            do_request_json_for( $as_user,
               method => "POST",
               uri    => "/api/v1/register",

               content => {
                  type => "m.login.application_service",
                  user => "astest-$user_id_fragment"
               },
            )->then( sub {
               my ( $body ) = @_;

               # TODO: user has no event stream yet. Should they?
               Future->done(
                  User( $as_user->http, $body->{user_id}, $body->{access_token}, undef, undef, [], undef )
               );
            });
         };

         Future->done(1);
      });
   };

test "AS cannot create users outside its own namespace",
   requires => [qw( as_user )],

   do => sub {
      my ( $as_user ) = @_;

      do_request_json_for( $as_user,
         method => "POST",
         uri    => "/api/v1/register",

         content => {
            type => "m.login.application_service",
            user => "a-different-user",
         }
      )->main::expect_http_4xx;
   };

test "Regular users cannot register within the AS namespace",
   requires => [qw( register_new_user first_api_client )],

   do => sub {
      my ( $register_new_user, $http ) = @_;

      $register_new_user->( $http, "astest-01create-2" )
         ->main::expect_http_4xx;
   };

my $room_id;
prepare "Creating a new test room",
   requires => [qw( make_test_room user )],

   do => sub {
      my ( $make_test_room, $user ) = @_;

      $make_test_room->( [ $user ] )
         ->on_done( sub {
            ( $room_id ) = @_;
         });
   };

test "AS can make room aliases",
   requires => [qw( await_as_event as_user first_home_server
                    can_create_room can_create_room_alias )],

   do => sub {
      my ( $await_as_event, $as_user, $first_home_server ) = @_;
      my $room_alias = "#astest-01create-1:$first_home_server";

      Future->needs_all(
         $await_as_event->( "m.room.aliases" )->then( sub {
            my ( $event ) = @_;

            log_if_fail "Event", $event;

            require_json_keys( $event, qw( content room_id user_id ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";
            $event->{user_id} eq $as_user->user_id or
               die "Expected user_id to be ${\$as_user->user_id}";

            require_json_keys( my $content = $event->{content}, qw( aliases ));
            require_json_list( my $aliases = $content->{aliases} );

            grep { $_ eq $room_alias } @$aliases or
               die "EXpected to find our alias in the aliases list";

            Future->done;
         }),

         do_request_json_for( $as_user,
            method => "PUT",
            uri    => "/api/v1/directory/room/$room_alias",

            content => {
               room_id => $room_id,
            },
         )
      )->then( sub {
         # Nothing interesting in the body

         do_request_json_for( $as_user,
            method => "GET",
            uri    => "/api/v1/directory/room/$room_alias",
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         require_json_keys( $body, qw( room_id ));

         $body->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id'";

         Future->done(1);
      });
   };

test "Regular users cannot create room aliases within the AS namespace",
   requires => [qw( do_request_json first_home_server
                    can_create_room can_create_room_alias )],

   do => sub {
      my ( $do_request_json, $first_home_server ) = @_;
      my $room_alias = "#astest-01create-2:$first_home_server";

      $do_request_json->(
         method => "PUT",
         uri    => "/api/v1/directory/room/$room_alias",

         content => {
            room_id => $room_id,
         }
      )->main::expect_http_4xx;
   };
