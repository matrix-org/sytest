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

      # skip this if the process never got started.
      return Future->done unless $server->pid;

      $OUTPUT->diag( "Killing ${\ $server->pid }" );

      $server->kill( 'INT' );

      Future->needs_any(
         $server->await_finish,

         $loop->delay_future( after => 30 )->then( sub {
            print STDERR "Timed out waiting for ${\ $server->pid }; sending SIGKILL\n";
            $server->kill( 'KILL' );
            Future->done;
         }),
      )
   } foreach => \@servers, concurrent => scalar @servers )->get;
};

push our @EXPORT, qw( HOMESERVER_INFO );

our @HOMESERVER_INFO = map {
   my $idx = $_;

   fixture(
      name => "HOMESERVER_$idx",

      requires => [ $main::TEST_SERVER_INFO, @main::AS_INFO ],

      setup => sub {
         my ( $test_server_info, @as_infos ) = @_;

         $OUTPUT->diag( "Starting Homeserver using $HS_FACTORY" );

         my $server = $HS_FACTORY->create_server(
            hs_dir              => abs_path( "server-$idx" ),
            hs_index            => $idx,
            bind_host           => $BIND_HOST,
            output              => $OUTPUT,
         );
         $loop->add( $server );

         my $location = $WANT_TLS ?
            "https://$BIND_HOST:" . $server->secure_port :
            "http://$BIND_HOST:" . $server->unsecure_port;

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

         my $info = ServerInfo( $server->server_name, $location );

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
                        { regex => '@_.*:' . $info->server_name, exclusive => "false" },
                        map { { regex => $_, exclusive => "true" } } @{ $as_info->user_regexes },
                     ],
                     aliases => [
                        map { { regex => $_, exclusive => "true" } } @{ $as_info->alias_regexes },
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

         Future->wait_any(
            $server->start,

            $loop->delay_future( after => 60 )
               ->then_fail( "Homeserver number $idx (on port ${\$server->secure_port}) failed to start" ),
         )->then_done( $info );
      },
   );
} 0 .. $N_HOMESERVERS-1;
