package SyTest::Synapse;

use strict;
use warnings;
use 5.010;
use base qw( IO::Async::Process );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   my $port = delete $args->{port};

   my $db = "homeserver-localhost-$port.db";
   my $db_rel = "../synapse/$db";
   unlink $db_rel if -f $db_rel;

   $args->{setup} = [
      chdir => delete $args->{synapse_dir},
   ];

   $args->{stderr} = {
      via => "pipe_read",
      on_read => sub { 0 }, # we'll read with Futures initially
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

1;
