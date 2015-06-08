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

prepare "Starting synapse",
   requires => [qw( synapse_ports synapse_args internal_server_port want_tls )],

   provides => [qw( synapse_client_locations )],

   do => sub {
      my ( $ports, $args, $internal_server_port, $want_tls ) = @_;

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
            ( scalar @{ $args->{log_filter} } ?
               ( filter_output => $args->{log_filter} ) :
               () ),

            config => {
               # Config for testing recaptcha. 90jira/SYT-8.pl
               recaptcha_siteverify_api => "http://localhost:$internal_server_port/recaptcha/api/siteverify",
               recaptcha_public_key     => "sytest_recaptcha_public_key",
               recaptcha_private_key    => "sytest_recaptcha_private_key",
            },
         );
         $loop->add( $synapse );

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
      });
   };
