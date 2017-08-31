use Digest::HMAC_SHA1 qw( hmac_sha1_hex );
use JSON qw( decode_json );

test "GET /register yields a set of flows",
   requires => [ $main::API_CLIENTS[0] ],

   proves => [qw( can_register_dummy_flow )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {},
      )->main::expect_http_401
      ->then( sub {
         my ( $response ) = @_;

         # Despite being an HTTP failure, the body is still JSON encoded and
         # has useful information
         assert_eq( $response->content_type, "application/json",
            'POST /r0/register results in application/json 401 failure'
         );

         my $body = decode_json( $response->content );
         log_if_fail "/r0/register flow information", $body;

         assert_json_keys( $body, qw( flows ));
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list";

         my $has_register_flow;

         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];

            # TODO(paul): Spec is a little vague here. Spec says that every
            #   option needs a 'stages' key, but the implementation omits it
            #   for options that have only one stage in their flow.
            ref $flow->{stages} eq "ARRAY" or defined $flow->{type} or
               die "Expected flow[$idx] to have 'stages' as a list or a 'type'";

            $has_register_flow++ if
               @{ $flow->{stages} } == 1 && $flow->{stages}[0] eq "m.login.dummy";
         }

         Future->done( $has_register_flow );
      });
   };

test "POST /register can create a user",
   requires => [ $main::API_CLIENTS[0],
                 qw( can_register_dummy_flow ) ],

   critical => 1,

   do => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            auth => {
               type => "m.login.dummy",
            },
            username => "01register-user",
            password => "s3kr1t",
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id access_token ));

         Future->done( 1 );
      });
   };

push our @EXPORT, qw( localpart_fixture );

my $next_anon_uid = 1;

sub sprintf_localpart
{
   sprintf "ANON-%d", $next_anon_uid++
}

sub localpart_fixture
{
   fixture(
      setup => sub {
         Future->done( sprintf_localpart() );
      },
   );
}

push @EXPORT, qw( matrix_register_user );

sub matrix_register_user
{
   my ( $http, $uid, %opts ) = @_;

   my $password = $opts{password} // "an0th3r s3kr1t";

   defined $uid or
      croak "Require UID for matrix_register_user";

   $http->do_request_json(
      method => "POST",
      uri    => "/r0/register",

      content => {
         auth => {
            type => "m.login.dummy",
         },
         bind_email => JSON::false,
         username   => $uid,
         password   => $password,
      },
   )->then( sub {
      my ( $body ) = @_;
      my $access_token = $body->{access_token};

      my $user = new_User(
         http         => $http,
         user_id      => $body->{user_id},
         device_id    => $body->{device_id},
         password     => $password,
         access_token => $access_token,
      );

      my $f = Future->done;

      if( $opts{with_events} // 1 ) {
         $f = $f->then( sub {
            $http->do_request_json(
               method => "GET",
               uri    => "/r0/events",
               params => { access_token => $access_token, timeout => 0 },
            )
         })->on_done( sub {
            my ( $body ) = @_;

            $user->eventstream_token = $body->{end};
         });
      }

      return $f->then_done( $user )
         ->on_done( sub {
            log_if_fail "Registered new user $uid";
         });
   });
}

push @EXPORT, qw( matrix_register_user_via_secret );

sub matrix_register_user_via_secret
{
   my ( $http, $uid, %opts ) = @_;

   my $password = $opts{password} // "an0th3r s3kr1t";
   my $is_admin = $opts{is_admin} // 0;

   defined $uid or
      croak "Require UID for matrix_register_user_via_secret";

   my $mac = hmac_sha1_hex(
      join( "\0", $uid, $password, $is_admin ? "admin" : "notadmin" ),
      "reg_secret"
   );

   $http->do_request_json(
      method => "POST",
      uri    => "/api/v1/register",

      content => {
        type     => "org.matrix.login.shared_secret",
        user     => $uid,
        password => $password,
        admin    => $is_admin ? JSON::true : JSON::false,
        mac      => $mac,
      },
   )->then( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, qw( user_id access_token ));

      my $access_token = $body->{access_token};

      my $user = new_User(
         http         => $http,
         user_id      => $body->{user_id},
         device_id    => $body->{device_id},
         password     => $password,
         access_token => $access_token,
      );

      return Future->done( $user )
        ->on_done( sub {
           log_if_fail "Registered new user (via secret) $uid";
        });
   });
}

test "POST /register with shared secret",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   proves => [qw( can_register_with_secret )],

   do => sub {
       my ( $http, $uid ) = @_;

       matrix_register_user_via_secret( $http, $uid, is_admin => 0 );
   };

test "POST /register admin with shared secret",
   requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

   do => sub {
       my ( $http, $uid ) = @_;

       matrix_register_user_via_secret( $http, $uid, is_admin => 1 );
   };

push @EXPORT, qw( local_user_fixture local_user_fixtures local_admin_fixture );

sub local_user_fixture
{
   my %args = @_;

   fixture(
      name => 'local_user_fixture',

      requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

      setup => sub {
         my ( $http, $localpart ) = @_;

         setup_user( $http, $localpart, %args );
      },
   );
}

sub local_admin_fixture
{
   my %args = @_;

   fixture(
      requires => [ $main::API_CLIENTS[0], localpart_fixture(), qw( can_register_with_secret ) ],

      setup => sub {
         my ( $http, $localpart ) = @_;

         matrix_register_user_via_secret( $http, $localpart, is_admin => 1, %args );
      },
   );
}

sub local_user_fixtures
{
   my ( $count, %args ) = @_;

   return map { local_user_fixture( %args ) } 1 .. $count;
}

push @EXPORT, qw( remote_user_fixture );

sub remote_user_fixture
{
   my %args = @_;

   fixture(
      name => "remote_user_fixture",

      requires => [ $main::API_CLIENTS[1], localpart_fixture() ],

      setup => sub {
         my ( $http, $localpart ) = @_;

         setup_user( $http, $localpart, %args )
      }
   );
}

sub setup_user
{
   my ( $http, $localpart, %args ) = @_;

   matrix_register_user( $http, $localpart,
      with_events => $args{with_events} // 1,
      password => $args{password},
   )->then_with_f( sub {
      my $f = shift;
      return $f unless defined( my $displayname = $args{displayname} );

      my $user = $f->get;
      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/profile/:user_id/displayname",

         content => { displayname => $displayname },
      )->then_done( $user );
   })->then_with_f( sub {
      my $f = shift;
      return $f unless defined( my $avatar_url = $args{avatar_url} );

      my $user = $f->get;
      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/profile/:user_id/avatar_url",

         content => { avatar_url => $avatar_url },
      )->then_done( $user );
   })->then_with_f( sub {
      my $f = shift;
      return $f unless defined( my $presence = $args{presence} );

      my $user = $f->get;
      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/presence/:user_id/status",

         content => {
            presence   => $presence,
            status_msg => ucfirst $presence,
         }
      )->then_done( $user );
   });
}


push @EXPORT, qw( matrix_create_user_on_server );

sub matrix_create_user_on_server
{
   my ( $http, %args ) = @_;

   setup_user( $http, sprintf_localpart(), %args )
}


push @EXPORT, qw( SPYGLASS_USER );

# A special user which we'll allow to be shared among tests, because we only
# allow it to perform HEAD and GET requests. This user is useful for tests that
# don't mutate server-side state, so it's fairly safe to reüse this user among
# different tests.
our $SPYGLASS_USER = fixture(
   requires => [ $main::API_CLIENTS[0] ],

   setup => sub {
      my ( $http ) = @_;

      matrix_register_user( $http, "spyglass" )
      ->on_done( sub {
         my ( $user ) = @_;

         $user->http = SyTest::HTTPClient->new(
            max_connections_per_host => 3,
            uri_base                 => $user->http->{uri_base}, # cheating

            restrict_methods => [qw( HEAD GET )],
         );

         $loop->add( $user->http );
      });
   },
);
