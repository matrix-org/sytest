use Future::Utils qw( fmap_void );

use SyTest::Homeserver::Synapse;

use Cwd qw( abs_path );

my $N_HOMESERVERS = 2;

sub extract_extra_args
{
   my ( $idx, $args ) = @_;

   return map {
      if( m/^\[(.*)\]$/ ) {
         # Extract the $idx'th element from a comma-separated list, or use the final
         my @choices = split m/,/, $1;
         $idx < @choices ? $choices[$idx] : $choices[-1];
      }
      else {
         $_;
      }
   } @$args;
}

my @synapses;

# Almost like an END block, but we can't use END because we need SIGCHLD, and
# see
#   https://rt.perl.org/Public/Bug/Display.html?id=128774
main::AT_END sub {
   $OUTPUT->diag( "Killing synapse servers " ) if @synapses;

   ( fmap_void {
      my $synapse = $_;

      $synapse->kill( 'INT' );

      Future->needs_any(
         $synapse->await_finish,

         $loop->delay_future( after => 30 )->then( sub {
            print STDERR "Timed out waiting for ${\ $synapse->pid }; sending SIGKILL\n";
            $synapse->kill( 'KILL' );
            Future->done;
         }),
      )
   } foreach => \@synapses, concurrent => scalar @synapses )->get;
};

push our @EXPORT, qw( HOMESERVER_INFO );

our @HOMESERVER_INFO = map {
   my $idx = $_;

   fixture(
      requires => [ $main::TEST_SERVER_INFO, @main::AS_INFO ],

      setup => sub {
         my ( $test_server_info, @as_infos ) = @_;

         my $secure_port   = main::alloc_port( "CLIENT[$idx].secure" );
         my $unsecure_port = main::alloc_port( "CLIENT[$idx].unsecure" );

         my @extra_args = extract_extra_args( $idx, $SYNAPSE_ARGS{extra_args} );

         my $location = $WANT_TLS ?
            "https://$BIND_HOST:$secure_port" :
            "http://$BIND_HOST:$unsecure_port";

         my $info = ServerInfo( "$BIND_HOST:$secure_port", $location );

         my $synapse = SyTest::Homeserver::Synapse->new(
            synapse_dir   => $SYNAPSE_ARGS{directory},
            hs_dir        => abs_path( "server-$idx" ),
            ports         => {
               client          => $secure_port,
               client_unsecure => $unsecure_port,

               synapse         => main::alloc_port( "synapse[$idx]" ),
               synapse_metrics => main::alloc_port( "synapse[$idx].metrics" ),

               pusher_metrics => main::alloc_port( "pusher[$idx].metrics" ),
               pusher_manhole => main::alloc_port( "pusher[$idx].manhole" ),

               synchrotron         => main::alloc_port( "synchrotron[$idx]" ),
               synchrotron_metrics => main::alloc_port( "synchrotron[$idx].metrics" ),
               synchrotron_manhole => main::alloc_port( "synchrotron[$idx].manhole" ),

               federation_reader         => main::alloc_port( "federation_reader[$idx]" ),
               federation_reader_metrics => main::alloc_port( "federation_reader[$idx].metrics" ),
               federation_reader_manhole => main::alloc_port( "federation_reader[$idx].manhole" ),

               media_repository => main::alloc_port( "media_repository[$idx]" ),
               media_repository_metrics => main::alloc_port( "media_repository[$idx].metrics" ),
               media_repository_manhole => main::alloc_port( "media_repository[$idx].manhole" ),

               appservice_metrics => main::alloc_port( "appservice[$idx].metrics" ),
               appservice_manhole => main::alloc_port( "appservice[$idx].manhole" ),

               federation_sender_metrics => main::alloc_port( "federation_sender1[$idx].metrics" ),
               federation_sender_manhole => main::alloc_port( "federation_sender[$idx].manhole" ),

               client_reader         => main::alloc_port( "client_reader[$idx]" ),
               client_reader_metrics => main::alloc_port( "client_reader[$idx].metrics" ),
               client_reader_manhole => main::alloc_port( "client_reader[$idx].manhole" ),
            },
            bind_host           => $BIND_HOST,
            output              => $OUTPUT,
            print_output        => $SYNAPSE_ARGS{log},
            extra_args          => \@extra_args,
            python              => $SYNAPSE_ARGS{python},
            coverage            => $SYNAPSE_ARGS{coverage},
            dendron             => $SYNAPSE_ARGS{dendron},
            pusher              => $SYNAPSE_ARGS{pusher},
            synchrotron         => $SYNAPSE_ARGS{synchrotron},
            federation_reader   => $SYNAPSE_ARGS{federation_reader},
            media_repository    => $SYNAPSE_ARGS{media_repository},
            appservice          => $SYNAPSE_ARGS{appservice},
            federation_sender   => $SYNAPSE_ARGS{federation_sender},
            client_reader       => $SYNAPSE_ARGS{client_reader},
            ( scalar @{ $SYNAPSE_ARGS{log_filter} } ?
               ( filter_output => $SYNAPSE_ARGS{log_filter} ) :
               () ),

            config => {
               # Config for testing recaptcha. 90jira/SYT-8.pl
               recaptcha_siteverify_api => $test_server_info->client_location .
                                              "/recaptcha/api/siteverify",
               recaptcha_public_key     => "sytest_recaptcha_public_key",
               recaptcha_private_key    => "sytest_recaptcha_private_key",

               user_agent_suffix => "homeserver[$idx]",

               cas_config => {
                  server_url => $test_server_info->client_location . "/cas",
                  service_url => $location,
               },
            },
         );
         $loop->add( $synapse );

         if( $idx == 0 ) {
            # Configure application services on first instance only
            my @confs;

            foreach my $idx ( 0 .. $#as_infos ) {
               my $as_info = $as_infos[$idx];

               my $appserv_conf = $synapse->write_yaml_file( "appserv-$idx.yaml", {
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
               $as_info->user_id = sprintf "@%s:$BIND_HOST:%d",
                  $as_info->localpart, $secure_port;
            }

            $synapse->append_config(
               app_service_config_files => \@confs,
            );
         }

         push @synapses, $synapse;

         Future->wait_any(
            $synapse->start,

            $loop->delay_future( after => 20 )
               ->then_fail( "Synapse server on port $secure_port failed to start" ),
         )->then_done( $info );
      },
   );
} 0 .. $N_HOMESERVERS-1;
