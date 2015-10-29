use SyTest::Synapse;

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

END {
   $output->diag( "Killing synapse servers " ) if @synapses;

   foreach my $synapse ( values @synapses ) {
      $synapse->kill( 'INT' );
   }
}

sub gen_token
{
   my ( $length ) = @_;
   return join "", map { chr 64 + rand 63 } 1 .. $length;
}

prepare "Starting synapse",
   requires => [qw( synapse_ports synapse_args test_http_server_uri_base want_tls )],

   provides => [qw(
      synapse_client_locations as_credentials hs2as_token rotate_logfiles rotate_first_logfile
   )],

   do => sub {
      my ( $ports, $args, $test_http_server_uri_base, $want_tls ) = @_;

      my @locations;

      Future->needs_all( map {
         my $idx = $_;

         my $secure_port = $ports->[$idx];
         my $unsecure_port = $want_tls ? 0 : $secure_port + 1000;

         my @extra_args = extract_extra_args( $idx, $args->{extra_args} );

         $locations[$idx] = $want_tls ?
            "https://localhost:$secure_port" :
            "http://localhost:$unsecure_port";

         my $synapse = SyTest::Synapse->new(
            synapse_dir   => $args->{directory},
            port          => $secure_port,
            unsecure_port => $unsecure_port,
            output        => $output,
            print_output  => $args->{log},
            extra_args    => \@extra_args,
            python        => $args->{python},
            coverage      => $args->{coverage},
            ( scalar @{ $args->{log_filter} } ?
               ( filter_output => $args->{log_filter} ) :
               () ),

            config => {
               # Config for testing recaptcha. 90jira/SYT-8.pl
               recaptcha_siteverify_api => "$test_http_server_uri_base/recaptcha/api/siteverify",
               recaptcha_public_key     => "sytest_recaptcha_public_key",
               recaptcha_private_key    => "sytest_recaptcha_private_key",

               use_insecure_ssl_client_just_for_testing_do_not_use => 1,
               report_stats => "False",
               user_agent_suffix => $locations[$idx],
               allow_guest_access => "True",
            },
         );
         $loop->add( $synapse );

         if( $idx == 0 ) {
            # Configure application services on first instance only
            my $appserv_conf = $synapse->write_yaml_file( "appserv.yaml", {
               url      => "$test_http_server_uri_base/appserv",
               as_token => ( my $as2hs_token = gen_token( 32 ) ),
               hs_token => ( my $hs2as_token = gen_token( 32 ) ),
               sender_localpart => ( my $as_user = "as-user" ),
               namespaces => {
                  users => [
                     { regex => '@astest-.*', exclusive => "true" },
                  ],
                  aliases => [
                     { regex => '#astest-.*', exclusive => "true" },
                  ],
                  rooms => [],
               }
            } );

            $synapse->append_config(
               app_service_config_files => [ $appserv_conf ],
            );

            provide as_credentials => [ "\@$as_user:localhost:$secure_port", $as2hs_token ];
            provide hs2as_token => $hs2as_token;
         }

         $synapse->start;

         push @synapses, $synapse;

         Future->wait_any(
            $synapse->started_future,

            $loop->delay_future( after => 20 )
               ->then_fail( "Synapse server on port $secure_port failed to start" ),
         );
      } 0 .. $#$ports )
      ->on_done( sub {
         provide synapse_client_locations => \@locations;

         my @rotate_logfiles = map {
            my $synapse = $_;
            sub { $synapse->rotate_logfile( @_ ) }
         } @synapses;

         provide rotate_logfiles      => \@rotate_logfiles;
         provide rotate_first_logfile => $rotate_logfiles[0];

         # TODO(paul):
         #   It might be nice to try to integrate this more into the core of
         #   the test system, such that any test can just declare it wants its
         #   own log file and the rotation happens automatically. Offhand I
         #   can't think of a neat way to arrange that without tying the test
         #   core too closely into this ability though. Maybe some new 'with'
         #   decorator that looks for 'with_'-prefixed testenv keys and
         #   codewraps the test...?
      });
   };
