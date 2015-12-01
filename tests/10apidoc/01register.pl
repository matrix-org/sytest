test "GET /register yields a set of flows",
   requires => [ $main::API_CLIENTS ],

   provides => [qw( can_register_password_flow )],

   check => sub {
      my ( $clients ) = @_;
      my $http = $clients->[0];

      $http->do_request_json(
         uri => "/api/v1/register",
      )->then( sub {
         my ( $body ) = @_;

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
               $flow->{type} eq "m.login.password" or
               @{ $flow->{stages} } == 1 && $flow->{stages}[0] eq "m.login.password";
         }

         $has_register_flow and
            provide can_register_password_flow => 1;

         Future->done(1);
      });
   };

test "POST /register can create a user",
   requires => [ $main::API_CLIENTS,
                 qw( can_register_password_flow ) ],

   critical => 1,

   do => sub {
      my ( $clients ) = @_;
      my $http = $clients->[0];

      $http->do_request_json(
         method => "POST",
         uri    => "/api/v1/register",

         content => {
            type     => "m.login.password",
            user     => "01register-user",
            password => "s3kr1t",
         },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( user_id access_token ));

         Future->done( 1 );
      });
   };

push our @EXPORT, qw( matrix_register_user );

my $next_anon_uid = 1;

sub matrix_register_user
{
   my ( $http, $uid, %opts ) = @_;

   $uid //= sprintf "_ANON_-%d", $next_anon_uid++;

   $http->do_request_json(
      method => "POST",
      uri    => "/api/v1/register",

      content => {
         type     => "m.login.password",
         user     => $uid,
         password => "an0th3r s3kr1t",
      },
   )->then( sub {
      my ( $body ) = @_;
      my $access_token = $body->{access_token};

      my $user = User( $http, $body->{user_id}, $access_token, undef, undef, [], undef );

      my $f = Future->done;

      if( $opts{with_events} // 1 ) {
         $f = $f->then( sub {
            $http->do_request_json(
               method => "GET",
               uri    => "/api/v1/events",
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

push @EXPORT, qw( local_user_fixture local_user_fixtures );

sub local_user_fixture
{
   my %args = @_;

   fixture(
      requires => [ $main::API_CLIENTS ],

      setup => sub {
         my ( $clients ) = @_;
         my $http = $clients->[0];

         matrix_register_user( $http, undef,
            with_events => $args{with_events} // 1,
         )->then_with_f( sub {
            my $f = shift;
            return $f unless defined( my $displayname = $args{displayname} );

            my $user = $f->get;
            do_request_json_for( $user,
               method => "PUT",
               uri    => "/api/v1/profile/:user_id/displayname",

               content => { displayname => $displayname },
            )->then_done( $user );
         })->then_with_f( sub {
            my $f = shift;
            return $f unless defined( my $presence = $args{presence} );

            my $user = $f->get;
            do_request_json_for( $user,
               method => "PUT",
               uri    => "/api/v1/presence/:user_id/status",

               content => {
                  presence   => $presence,
                  status_msg => ucfirst $presence,
               }
            )->then_done( $user );
         });
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
   fixture(
      requires => [ $main::API_CLIENTS ],

      setup => sub {
         my ( $clients ) = @_;
         my $http = $clients->[1];

         matrix_register_user( $http )
      }
   );
}

push @EXPORT, qw( SPYGLASS_USER );

# A special user which we'll allow to be shared among tests, because we only
# allow it to perform HEAD and GET requests. This user is useful for tests that
# don't mutate server-side state, so it's fairly safe to reüse this user among
# different tests.
our $SPYGLASS_USER = fixture(
   requires => [ $main::API_CLIENTS ],

   setup => sub {
      my ( $clients ) = @_;
      my $http = $clients->[0];

      matrix_register_user( $http )
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
