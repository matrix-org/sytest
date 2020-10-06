use Future::Utils qw( fmap_void );

use Cwd qw( abs_path );

my $N_HOMESERVERS = 2;

my @servers;

# Almost like an END block, but we can't use END because we need SIGCHLD, and
# see
#   https://rt.perl.org/Public/Bug/Display.html?id=128774
main::AT_END sub {
   ( fmap_void {
      my $server = $_;
      $server->kill_and_await_finish;
   } foreach => \@servers, concurrent => scalar @servers )->get;
};

push our @EXPORT, qw( HOMESERVER_INFO );

our @HOMESERVER_INFO = map {
   my $idx = $_;

   fixture(
      name => "HOMESERVER_$idx",

      requires => [ $main::TEST_SERVER_INFO, $main::MAIL_SERVER_INFO, @main::AS_INFO ],

      setup => sub {
         my ( $test_server_info, $mail_server_info, @as_infos ) = @_;

         $OUTPUT->diag( "Starting Homeserver using $HS_FACTORY" );

         my $server = eval { $HS_FACTORY->create_server(
            hs_dir              => abs_path( $main::WORK_DIR . "/server-$idx" ),
            hs_index            => $idx,
            bind_host           => $BIND_HOST,
            output              => $OUTPUT,
         ) };

         if ( ! $server ) {
            # if we couldn't create the first homeserver, fail hard. Otherwise
            # skip the dependent tests.
            if ( $idx == 0 ) {
               return Future->fail($@);
            }

            my $r = $@; chomp $r;
            return Future->fail("SKIP: $r");
         }

         $loop->add( $server );

         my $api_host = $server->http_api_host;

         my $location = $WANT_TLS ?
            "https://$api_host:" . $server->secure_port :
            "http://$api_host:" . $server->unsecure_port;

         $server->configure(
            smtp_server_config => $mail_server_info,
         );

         $server->configure(
            # Config for testing recaptcha. 90jira/SYT-8.pl
            recaptcha_config => {
               siteverify_api   => $test_server_info->client_location .
                                       "/recaptcha/api/siteverify",
               public_key       => "sytest_recaptcha_public_key",
               private_key      => "sytest_recaptcha_private_key",
            }, cas_config    => {
               server_url       => $test_server_info->client_location . "/cas",
               service_url      => $location,
            },
         );

         my $info = ServerInfo( $server->server_name, $location,
                                $api_host, $server->federation_port );

         if( $idx == 0 ) {
            # Configure application services on first instance only
            my @confs;

            foreach my $idx ( 0 .. $#as_infos ) {
               my $as_info = $as_infos[$idx];

               my $appserv_conf = $server->write_yaml_file( "appserv-$idx.yaml", {
                  id       => $as_info->id,
                  url      => $test_server_info->client_location . $as_info->path,
                  as_token => $as_info->as2hs_token,
                  hs_token => $as_info->hs2as_token,
                  sender_localpart => $as_info->localpart,
                  namespaces => {
                     users => [
                        { regex => '@_.*:' . $info->server_name, exclusive => JSON::false },
                        map { { regex => $_, exclusive => JSON::true } } @{ $as_info->user_regexes },
                     ],
                     aliases => [
                        map { { regex => $_, exclusive => JSON::true } } @{ $as_info->alias_regexes },
                     ],
                     rooms => [],
                  },
                  protocols => $as_info->protocols,
               } );

               push @confs, $appserv_conf;

               # Now we can fill in the AS info's user_id
               $as_info->user_id = sprintf "@%s:%s",
                  $as_info->localpart, $server->server_name;
            }

            $server->configure(
               app_service_config_files => \@confs,
            );
         }

         push @servers, $server;

         $OUTPUT->diag( "Starting server-$idx" );
         Future->wait_any(
            $server->start,

            $loop->delay_future( after => 60 )
               ->then_fail( "Timeout waiting for HS to start" ),
         )->then( sub {
            $OUTPUT->diag( "Started server-$idx" );
            return Future->done( $info );
         })->on_fail( sub {
            my ( $exn, @details ) = @_;
            warn( "Error starting server-$idx (on port ${\$server->secure_port}): $exn" );

            # if we can't start the first homeserver, we really might as well go home.
            if( $idx == 0 ) {
               print STDERR "\nAborting test run due to failure to start test server\n";

               # If we just exit then we need to call the AT_END functions
               # manually (if we don't we'll leak child processes).
               run_AT_END;
               exit 1;
            }
         })
      },
   );
} 0 .. $N_HOMESERVERS-1;
