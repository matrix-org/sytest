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
   $OUTPUT->diag( "Killing synapse servers " ) if @synapses;

   foreach my $synapse ( values @synapses ) {
      $synapse->kill( 'INT' );
   }
}

sub gen_token
{
   my ( $length ) = @_;
   return join "", map { chr 64 + rand 63 } 1 .. $length;
}

push our @EXPORT, qw( AS_USER_INFO HOMESERVER_INFO );

struct ASUserInfo => [qw( localpart user_id as2hs_token hs2as_token )];

our $AS_USER_INFO = fixture(
   setup => sub {
      my $port = $HOMESERVER_PORTS[0];

      my $localpart = "as-user";

      Future->done( ASUserInfo(
         $localpart,
         "\@${localpart}:localhost:${port}",
         gen_token( 32 ),
         gen_token( 32 ),
      ));
   },
);

our @HOMESERVER_INFO = map {
   my $idx = $_;

   fixture(
      requires => [ $main::TEST_SERVER_INFO, $AS_USER_INFO ],

      setup => sub {
         my ( $test_server_info, $as_user_info ) = @_;

         my $secure_port = $HOMESERVER_PORTS[$idx];
         my $unsecure_port = $WANT_TLS ? 0 : $secure_port + 1000;

         my @extra_args = extract_extra_args( $idx, $SYNAPSE_ARGS{extra_args} );

         my $location = $WANT_TLS ?
            "https://localhost:$secure_port" :
            "http://localhost:$unsecure_port";

         my $info = ServerInfo( "localhost:$secure_port", $location );

         my $synapse = SyTest::Synapse->new(
            synapse_dir   => $SYNAPSE_ARGS{directory},
            port          => $secure_port,
            unsecure_port => $unsecure_port,
            output        => $OUTPUT,
            print_output  => $SYNAPSE_ARGS{log},
            extra_args    => \@extra_args,
            python        => $SYNAPSE_ARGS{python},
            coverage      => $SYNAPSE_ARGS{coverage},
            ( scalar @{ $SYNAPSE_ARGS{log_filter} } ?
               ( filter_output => $SYNAPSE_ARGS{log_filter} ) :
               () ),

            config => {
               # Config for testing recaptcha. 90jira/SYT-8.pl
               recaptcha_siteverify_api => $test_server_info->client_location .
                                              "/recaptcha/api/siteverify",
               recaptcha_public_key     => "sytest_recaptcha_public_key",
               recaptcha_private_key    => "sytest_recaptcha_private_key",

               use_insecure_ssl_client_just_for_testing_do_not_use => 1,
               report_stats => "False",
               user_agent_suffix => $location,
               allow_guest_access => "True",
            },
         );
         $loop->add( $synapse );

         if( $idx == 0 ) {
            # Configure application services on first instance only
            my $appserv_conf = $synapse->write_yaml_file( "appserv.yaml", {
               url      => $test_server_info->client_location . "/appserv",
               as_token => $as_user_info->as2hs_token,
               hs_token => $as_user_info->hs2as_token,
               sender_localpart => $as_user_info->localpart,
               namespaces => {
                  users => [
                     { regex => '@astest-.*', exclusive => "true" },
                  ],
                  aliases => [
                     { regex => '#astest-.*', exclusive => "true" },
                  ],
                  rooms => [],
               },
               ratelimit => "false",
            } );

            $synapse->append_config(
               app_service_config_files => [ $appserv_conf ],
            );
         }

         $synapse->start;

         push @synapses, $synapse;

         Future->wait_any(
            $synapse->started_future,

            $loop->delay_future( after => 20 )
               ->then_fail( "Synapse server on port $secure_port failed to start" ),
         )->then_done( $info );
      },
   );
} 0 .. $#HOMESERVER_PORTS;
