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
   requires => [qw( )],

   provides => [qw( )],

   ## TODO: This preparation step relies on sneaky visibility of the @PORTS,
   #    $SYNAPSE_EXTRA_ARGS, $SYNAPSE_DIR, $SERVER_LOG, $PYTHON,
   #    $SERVER_FILTER and $NO_SSL variables defined at toplevel

   do => sub {
      Future->needs_all( map {
         my $idx = $_;
         my $port = $PORTS[$idx];

         my @extra_args = extract_extra_args( $idx, \@SYNAPSE_EXTRA_ARGS );

         my $synapse = SyTest::Synapse->new(
            synapse_dir  => $SYNAPSE_DIR,
            port         => $port,
            output       => $output,
            print_output => $SERVER_LOG,
            extra_args   => \@extra_args,
            python       => $PYTHON,
            no_ssl       => $NO_SSL,
            ( @SERVER_FILTER ? ( filter_output => \@SERVER_FILTER ) : () ),

            internal_server_port => $internal_server_port,  # temporary hack
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
