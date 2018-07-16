my $user_fixture = local_user_fixture();

my $room_fixture = room_fixture( $user_fixture );

test "AS can create a user",
   requires => [ $main::AS_USER[0], $room_fixture ],

   do => sub {
      my ( $as_user, $room_id ) = @_;

      do_request_json_for( $as_user,
         method => "POST",
         uri    => "/r0/register",

         content => {
            user => "astest-01create-0-$TEST_RUN_ID",
         },
      )->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( user_id home_server access_token device_id ));

         Future->done(1);
      });
   };

test "AS can create a user with inhibit_login",
   requires => [ $main::AS_USER[0], $room_fixture ],

   do => sub {
      my ( $as_user, $room_id ) = @_;

      do_request_json_for( $as_user,
         method => "POST",
         uri    => "/r0/register",

         content => {
            user => "astest-01create-1-$TEST_RUN_ID",
            inhibit_login => 1,
         },
      )->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( user_id home_server ));
         foreach ( qw( device_id access_token )) {
            exists $body->{$_} and die "Got an unexpected a '$_' key";
         }

         Future->done(1);
      });
   };

test "AS can create a user via the legacy /v1 endpoint",
   requires => [ $main::AS_USER[0], $room_fixture ],

   do => sub {
      my ( $as_user, $room_id ) = @_;

      do_request_json_for( $as_user,
         method => "POST",
         uri    => "/api/v1/register",

         content => {
            type => "m.login.application_service",
            user => "astest-01create-2-$TEST_RUN_ID",
         },
      )->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( user_id home_server ));

         Future->done(1);
      });
   };

test "AS cannot create users outside its own namespace",
   requires => [ $main::AS_USER[0] ],

   do => sub {
      my ( $as_user ) = @_;

      do_request_json_for( $as_user,
         method => "POST",
         uri    => "/r0/register",

         content => {
            user => "a-different-user",
         }
      )->main::expect_http_4xx;
   };

test "Regular users cannot register within the AS namespace",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      matrix_register_user( $http, "astest-01create-3-$TEST_RUN_ID" )
         ->main::expect_http_4xx;
   };

test "AS can make room aliases",
   requires => [
      $main::AS_USER[0], $main::APPSERV[0], $room_fixture,
      room_alias_fixture( prefix => "astest-" ),
      qw( can_create_room_alias ),
   ],

   do => sub {
      my ( $as_user, $appserv, $room_id, $room_alias ) = @_;

      Future->needs_all(
         $appserv->await_event( "m.room.aliases" )->then( sub {
            my ( $event, $request ) = @_;

            # As this is the first AS event we've received, lets check that the
            # token matches, to give that coverage.

            my $access_token = $request->query_param( "access_token" );

            assert_ok( defined $access_token,
               "HS provides an access_token" );
            assert_eq( $access_token, $appserv->info->hs2as_token,
               "HS provides the correct token" );

            log_if_fail "Event", $event;

            assert_json_keys( $event, qw( content room_id user_id ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";
            $event->{user_id} eq $as_user->user_id or
               die "Expected user_id to be ${\$as_user->user_id}";

            assert_json_keys( my $content = $event->{content}, qw( aliases ));
            assert_json_list( my $aliases = $content->{aliases} );

            grep { $_ eq $room_alias } @$aliases or
               die "EXpected to find our alias in the aliases list";

            Future->done;
         }),

         do_request_json_for( $as_user,
            method => "PUT",
            uri    => "/r0/directory/room/$room_alias",

            content => {
               room_id => $room_id,
            },
         )
      )->then( sub {
         # Nothing interesting in the body

         do_request_json_for( $as_user,
            method => "GET",
            uri    => "/r0/directory/room/$room_alias",
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( room_id ));

         $body->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id'";

         Future->done(1);
      });
   };

test "Regular users cannot create room aliases within the AS namespace",
   requires => [
      $user_fixture, $room_fixture, room_alias_fixture( prefix => "astest-" ),
      qw( can_create_room_alias ),
   ],

   do => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/directory/room/$room_alias",

         content => {
            room_id => $room_id,
         }
      )->main::expect_http_4xx;
   };

push our @EXPORT, qw( matrix_register_as_ghost as_ghost_fixture );

sub matrix_register_as_ghost
{
   my ( $as_user, $user_id ) = @_;
   is_User( $as_user ) or croak "Expected a User, got $as_user";

   do_request_json_for( $as_user,
      method => "POST",
      uri    => "/r0/register",

      content => {
         user => $user_id,
      }
   )->then( sub {
      my ( $body ) = @_;

      # TODO: user has no event stream yet. Should they?
      Future->done( new_User(
         http         => $as_user->http,
         user_id      => $body->{user_id},
         access_token => $body->{access_token},
      ));
   });
}

my $next_as_user_id = 0;
sub as_ghost_fixture
{
   my ( $idx ) = @_;
   $idx //= 0;

   fixture(
      requires => [ $main::AS_USER[$idx] ],

      setup => sub {
         my ( $as_user ) = @_;

         my $user_id = "astest-$next_as_user_id-$TEST_RUN_ID";
         $next_as_user_id++;

         matrix_register_as_ghost( $as_user, $user_id );
      },
   );
}
