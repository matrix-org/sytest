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
   requires => [qw( synapse_args internal_server_port )],

   provides => [qw( )],

   ## TODO: This preparation step relies on sneaky visibility of the @PORTS
   #    and $NO_SSL variables defined at toplevel

   do => sub {
      my ( $args, $internal_server_port ) = @_;

      Future->needs_all( map {
         my $idx = $_;
         my $port = $PORTS[$idx];

         my @extra_args = extract_extra_args( $idx, $args->{extra_args} );

         my $synapse = SyTest::Synapse->new(
            synapse_dir  => $args->{directory},
            port         => $port,
            output       => $output,
            print_output => $args->{log},
            extra_args   => \@extra_args,
            python       => $args->{python},
            no_ssl       => $NO_SSL,
            ( scalar @{ $args->{log_filter} } ?
               ( filter_output => $args->{log_filter} ) :
               () ),

            internal_server_port => $internal_server_port,
         );
         $loop->add( $synapse );

         push @synapses, $synapse;

         Future->wait_any(
            $synapse->started_future,

            $loop->delay_future( after => 20 )
               ->then_fail( "Synapse server on port $port failed to start" ),
         );
      } 0 .. $#PORTS );
   };
