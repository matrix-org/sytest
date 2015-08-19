# A handy little structure for other scripts to find in 'user' and 'more_users'
struct User => [qw( http user_id access_token refresh_token eventstream_token saved_events pending_get_events )];

test "GET /login yields a set of flows",
   requires => [qw( first_v1_client )],

   provides => [qw( can_login_password_flow )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request_json(
         uri => "/login",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( flows ));
         ref $body->{flows} eq "ARRAY" or die "Expected 'flows' as a list";

         my $has_login_flow;

         foreach my $idx ( 0 .. $#{ $body->{flows} } ) {
            my $flow = $body->{flows}[$idx];

            # TODO(paul): Spec is a little vague here. Spec says that every
            #   option needs a 'stages' key, but the implementation omits it
            #   for options that have only one stage in their flow.
            ref $flow->{stages} eq "ARRAY" or defined $flow->{type} or
               die "Expected flow[$idx] to have 'stages' as a list or a 'type'";

            $has_login_flow++ if $flow->{type} eq "m.login.password" or
               @{ $flow->{stages} } == 1 && $flow->{stages}[0] eq "m.login.password"
         }

         $has_login_flow and
            provide can_login_password_flow => 1;

         Future->done(1);
      });
   };

test "POST /login can log in as a user",
   requires => [qw( first_v1_client can_register can_login_password_flow )],

   provides => [qw( can_login user first_home_server do_request_json_for do_request_json )],

   do => sub {
      my ( $http, $login_details ) = @_;
      my ( $user_id, $password ) = @$login_details;

      $http->do_request_json(
         method => "POST",
         uri    => "/login",

         content => {
            type     => "m.login.password",
            user     => $user_id,
            password => $password,
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( access_token home_server ));

         provide can_login => 1;

         my $access_token = $body->{access_token};
         my $refresh_token = $body->{refresh_token};

         provide user => my $user = User( $http, $user_id, $access_token, $refresh_token, undef, [], undef );

         provide first_home_server => $body->{home_server};

         provide do_request_json_for => my $do_request_json_for = sub {
            my ( $user, %args ) = @_;

            my $user_id = $user->user_id;
            ( my $uri = delete $args{uri} ) =~ s/:user_id/$user_id/g;

            my %params = (
               access_token => $user->access_token,
               %{ delete $args{params} || {} },
            );

            $user->http->do_request_json(
               uri    => $uri,
               params => \%params,
               %args,
            );
         };

         provide do_request_json => sub {
            $do_request_json_for->( $user, @_ );
         };

         Future->done(1);
      });
   };

test "POST /login wrong password is rejected",
   requires => [qw( first_v1_client can_register can_login_password_flow )],

   do => sub {
      my ( $http, $login_details ) = @_;
      my ( $user_id, $password ) = @$login_details;

      $http->do_request_json(
         method => "POST",
         uri    => "/login",

         content => {
            type     => "m.login.password",
            user     => $user_id,
            password => "${password}wrong",
         },
      )->then(
         sub { # done
            Future->fail( "Expected not to succeed in logging in" );
         },
         sub { # fail
            my ( $failure, $name, @args ) = @_;

            defined $name and $name eq "http" or
               die "Expected failure kind to be 'http'";

            my ( $resp, $req ) = @args;

            $resp->code == 403 or
               die "Expected HTTP response code to be 403";

            my $body = decode_json($resp->{_content});
            require_json_keys( $body, qw( errcode ));

            my $errcode = $body->{errcode};

            $errcode eq "M_FORBIDDEN" or
               die "Expected errcode to be M_FORBIDDEN but was ${errcode}";

            Future->done(1);
         },
      );
   };

test "POST /tokenrefresh invalidates old refresh token",
   requires => [qw( first_v2_client user )],
   provides => [qw( refreshed_user )],

   do => sub {
      my ( $http, $old_user ) = @_;
      $http->do_request_json(
         method => "POST",
         uri    => "/tokenrefresh",

         content => {
            refresh_token => $old_user->refresh_token,
         },
      )->then(
         sub {
            my ( $body ) = @_;
            require_json_keys( $body, qw( access_token refresh_token ));
            my $new_access_token = $body->{access_token};
            my $new_refresh_token = $body->{refresh_token};

            $new_access_token ne $old_user->access_token or
               die "Expected new access token";

            $new_refresh_token ne $old_user->refresh_token or
               die "Expected new refresh token";

            provide refreshed_user => my $refreshed_user = User(
               $old_user->http,
               $old_user->user_id,
               $new_access_token,
               $new_refresh_token,
               $old_user->eventstream_token,
               $old_user->saved_events,
               $old_user->pending_get_events
            );

            $http->do_request_json(
               method => "POST",
               uri    => "/tokenrefresh",

               content => {
                  refresh_token => $old_user->refresh_token,
               },
            )
         }
      )->then(
         sub { # done
            Future->fail( "Expected not to succeed in re-using refresh token" );
         },
         sub { # fail
            my ( $failure, $name, @args ) = @_;

            defined $name and $name eq "http" or
               die "Expected failure kind to be 'http'";

            my ( $resp, $req ) = @args;

            $resp->code == 403 or
               die "Expected HTTP response code to be 403 but was ${\$resp->code}";

            Future->done(1);
         }
      )
   };
