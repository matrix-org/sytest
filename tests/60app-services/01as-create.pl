my $user_fixture = local_user_fixture();

my $room_fixture = room_fixture(
   requires_users => [ $user_fixture ],
);

our $AS_USER;

test "AS can create a user",
   requires => [ $AS_USER, $room_fixture ],

   do => sub {
      my ( $as_user, $room_id ) = @_;

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

         assert_json_keys( $body, qw( user_id home_server ));

         Future->done(1);
      });
   };

test "AS cannot create users outside its own namespace",
   requires => [ $AS_USER ],

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
   requires => [ $main::API_CLIENTS ],

   do => sub {
      my ( $clients ) = @_;
      my $http = $clients->[0];

      matrix_register_user( $http, "astest-01create-2" )
         ->main::expect_http_4xx;
   };

test "AS can make room aliases",
   requires => [ $AS_USER, qw( hs2as_token first_home_server ), $room_fixture,
                qw( can_create_room_alias )],

   do => sub {
      my ( $as_user, $hs2as_token, $first_home_server, $room_id ) = @_;
      my $room_alias = "#astest-01create-1:$first_home_server";

      Future->needs_all(
         await_as_event( "m.room.aliases" )->then( sub {
            my ( $event, $request ) = @_;

            # As this is the first AS event we've received, lets check that the
            # token matches, to give that coverage.

            my $access_token = $request->query_param( "access_token" );

            assert_ok( defined $access_token,
               "HS provides an access_token" );
            assert_eq( $access_token, $hs2as_token,
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

         assert_json_keys( $body, qw( room_id ));

         $body->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id'";

         Future->done(1);
      });
   };

test "Regular users cannot create room aliases within the AS namespace",
   requires => [qw( first_home_server ), $user_fixture, $room_fixture,
                qw( can_create_room_alias )],

   do => sub {
      my ( $first_home_server, $user, $room_id ) = @_;
      my $room_alias = "#astest-01create-2:$first_home_server";

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/directory/room/$room_alias",

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
      uri    => "/api/v1/register",

      content => {
         type => "m.login.application_service",
         user => $user_id,
      }
   )->then( sub {
      my ( $body ) = @_;

      # TODO: user has no event stream yet. Should they?
      Future->done(
         User( $as_user->http, $body->{user_id}, $body->{access_token}, undef, undef, [], undef )
      );
   });
}

my $next_as_user_id = 0;
sub as_ghost_fixture
{
   fixture(
      requires => [ $AS_USER ],

      setup => sub {
         my ( $as_user ) = @_;

         my $user_id = "astest-$next_as_user_id";
         $next_as_user_id++;

         matrix_register_as_ghost( $as_user, $user_id );
      },
   );
}
