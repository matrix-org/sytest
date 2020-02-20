use utf8;

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

   do => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            auth => {
               type => "m.login.dummy",
            },
            username => "01register-user-".$TEST_RUN_ID,
            password => "sUp3rs3kr1t",
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id access_token ));

         Future->done( 1 );
      });
   };

test "POST /register downcases capitals in usernames",
   requires => [ $main::API_CLIENTS[0],
                 qw( can_register_dummy_flow ) ],

   do => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            auth => {
               type => "m.login.dummy",
            },
            username => "user-UPPER",
            password => "sUp3rs3kr1t",
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id access_token ));
         assert_eq( $body->{user_id}, '@user-upper:' . $http->{server_name}, 'user_id' );

         Future->done( 1 );
      });
   };

test "POST /register returns the same device_id as that in the request",
   requires => [ $main::API_CLIENTS[0],
                 qw( can_register_dummy_flow ) ],

   do => sub {
      my ( $http ) = @_;

      my $device_id = "my_device_id";

      $http->do_request_json(
         method => "POST",
         uri    => "/r0/register",

         content => {
            auth => {
               type => "m.login.dummy",
            },
            username => "mycooluser",
            password => "sUp3rs3kr1t",
            device_id => $device_id,
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( device_id ));
         assert_eq( $body->{device_id}, $device_id, 'device_id' );

         Future->done( 1 );
      });
   };


foreach my $chr (split '', '!":?\@[]{|}£é' . "\n'" ) {
   my $q = $chr; $q =~ s/\n/\\n/;

   test "POST /register rejects registration of usernames with '$q'",
      requires => [ $main::API_CLIENTS[0],
                    qw( can_register_dummy_flow ) ],

      do => sub {
         my ( $http ) = @_;

         my $reqbody = {
            auth => {
               type => "m.login.dummy",
            },
            username => 'chrtestuser-'.ord($chr)."-",
            password => "sUp3rs3kr1t",
         };

         # registration without the dodgy char should be ok
         $http->do_request_json(
            method => "POST",
            uri    => "/r0/register",

            content => $reqbody,
         )->then( sub {
            # registration with the dodgy char should 400
            $reqbody->{username} .= $chr;
            $http->do_request_json(
               method => "POST",
               uri    => "/r0/register",
               content => $reqbody,
            );
         })->main::expect_http_400()
            ->then( sub {
               my ( $response ) = @_;
               my $body = decode_json( $response->content );
               assert_eq( $body->{errcode}, "M_INVALID_USERNAME", 'responsecode' );
               Future->done( 1 );
            });
      };
}

push our @EXPORT, qw( localpart_fixture );

my $next_anon_uid = 1;

sub sprintf_localpart
{
   sprintf "anon-%s-%d", $TEST_RUN_ID, $next_anon_uid++
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

      if( $opts{with_events} ) {
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
            log_if_fail "Registered new user ". $user->user_id;
         });
   });
}

shared_secret_tests( "/r0/admin/register", \&matrix_admin_register_user_via_secret);

sub matrix_admin_register_user_via_secret
{
   my ( $http, $uid, %opts ) = @_;

   my $password = $opts{password} // "an0th3r s3kr1t";
   my $is_admin = $opts{is_admin} // 0;

   defined $uid or
      croak "Require UID for matrix_register_user_via_secret";

   $http->do_request_json(
      method => "GET",
      uri    => "/r0/admin/register",
   )->then( sub{
      my ( $nonce ) = @_;

      my $mac = hmac_sha1_hex(
         join( "\0", $nonce->{nonce}, $uid, $password, $is_admin ? "admin" : "notadmin" ),
         "reg_secret"
      );

      return $http->do_request_json(
         method => "POST",
         uri    => "/r0/admin/register",

         content => {
           nonce    => $nonce->{nonce},
           username => $uid,
           password => $password,
           admin    => $is_admin ? JSON::true : JSON::false,
           mac      => $mac,
         },
      )
   })->then( sub {
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
           log_if_fail "Registered new user (via secret) " . $user->user_id;
        });
   });
}

sub shared_secret_tests {
   my ( $ep_name, $register_func ) = @_;

   test "POST $ep_name with shared secret",
      requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

      proves => [qw( can_register_with_secret )],

      do => sub {
         my ( $http, $uid ) = @_;

         $register_func->( $http, $uid, is_admin => 0 )
         ->then( sub {
            my ( $user ) = @_;
            assert_eq( $user->user_id, "\@$uid:" . $http->{server_name}, 'userid' );
            Future->done( 1 );
         });
      };

   test "POST $ep_name admin with shared secret",
      requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

      do => sub {
         my ( $http, $uid ) = @_;

         $register_func->( $http, $uid, is_admin => 1 )
         ->then( sub {
            my ( $user ) = @_;
            assert_eq( $user->user_id, "\@$uid:" . $http->{server_name}, 'userid' );
            # TODO: test it is actually an admin
            Future->done( 1 );
         });
      };

   test "POST $ep_name with shared secret downcases capitals",
      requires => [ $main::API_CLIENTS[0], localpart_fixture() ],

      proves => [qw( can_register_with_secret )],

      do => sub {
         my ( $http, $localpart ) = @_;

         $register_func->( $http, $localpart . "A", is_admin => 0 )
         ->then( sub {
            my ( $user ) = @_;
            assert_eq( $user->user_id, '@' . $localpart . 'a:' . $http->{server_name}, 'userid' );
            Future->done( 1 );
         });
      };

   test "POST $ep_name with shared secret disallows symbols",
      requires => [ $main::API_CLIENTS[0] ],

      proves => [qw( can_register_with_secret )],

      do => sub {
         my ( $http ) = @_;

         $register_func->( $http, "us,er", is_admin => 0 )
         ->main::expect_http_400()
         ->then( sub {
            my ( $response ) = @_;
            my $body = decode_json( $response->content );
            assert_eq( $body->{errcode}, "M_INVALID_USERNAME", 'errcode' );
            Future->done( 1 );
         });
      };
}

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

         matrix_admin_register_user_via_secret( $http, $localpart, is_admin => 1, %args );
      },
   );
}

sub local_user_fixtures
{
   my ( $count, %args ) = @_;

   return map { local_user_fixture( %args ) } 1 .. $count;
}

push @EXPORT, qw( remote_user_fixture );

sub remote_admin_fixture
{
   my %args = @_;

   fixture(
      requires => [ $main::API_CLIENTS[1], localpart_fixture(), qw( can_register_with_secret ) ],

      setup => sub {
         my ( $http, $localpart ) = @_;

         matrix_admin_register_user_via_secret( $http, $localpart, is_admin => 1, %args );
      },
   );
}
push @EXPORT, qw( remote_admin_fixture );

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
      with_events => $args{with_events} // 0,
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
