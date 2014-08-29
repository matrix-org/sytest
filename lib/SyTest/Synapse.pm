package SyTest::Synapse;

use strict;
use warnings;
use 5.010;
use base qw( IO::Async::Process );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   my $port = $self->{port} = delete $args->{port};
   $self->{print_output} = delete $args->{print_output};

   my $db = "homeserver-localhost-$port.db";
   my $db_rel = "../synapse/$db";
   unlink $db_rel if -f $db_rel;

   $args->{setup} = [
      chdir => delete $args->{synapse_dir},
   ];

   $args->{stderr} = {
      via => "pipe_read",
      on_read => $self->_capture_weakself( 'on_synapse_read' ),
   };

   $args->{command} = [
      "python", "synapse/app/homeserver.py",
         "--host" => "localhost:$port",
         "--port" => $port,
         "--database" => $db,
   ];

   $self->SUPER::_init( $args );
}

sub on_finish
{
   my $self = shift;
   say $self->pid . " stopped";
}

sub on_synapse_read
{
   my $self = shift;
   my ( $proc, $bufref, $eof ) = @_;

   while( $$bufref =~ s/^(.*)\n// ) {
      my $line = $1;
      print STDERR "\e[1;35m[server $self->{port}]\e[m: $line\n" if $self->{print_output};

      $self->started_future->done if $line =~ m/INFO - Synapse now listening on port \d+\s*$/;
   }

   return 0;
}

sub started_future
{
   my $self = shift;
   return $self->{started_future} ||= $self->loop->new_future;
}

1;
