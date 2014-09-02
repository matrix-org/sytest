package SyTest::Synapse;

use strict;
use warnings;
use 5.010;
use base qw( IO::Async::Notifier );

use IO::Async::Process;

use File::chdir;
use File::Path qw( make_path );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw( port print_output synapse_dir );

   $self->SUPER::_init( $args );
}

sub _add_to_loop
{
   my $self = shift;
   my ( $loop ) = @_;

   my $port = $self->{port};

   my $hs_dir = "localhost-$port";
   my $db = "$hs_dir/homeserver.db";

   {
      local $CWD = $self->{synapse_dir};

      -d $hs_dir or make_path $hs_dir;
      unlink $db if -f $db;
   }

   my @command = (
      "python", "synapse/app/homeserver.py",
         "--config-path" => "$hs_dir/config",

         "--server-name" => "localhost:$port",
         "--bind-port"   => $port,
         "--database"    => $db,

         # TLS parameters
         "--tls-dh-params-path" => "$CWD/keys/tls.dh",
   );

   print STDERR "Generating config for port $port\n";

   $loop->run_child(
      setup => [
         chdir => $self->{synapse_dir},
      ],

      command => [ @command, "--generate-config" ],

      on_finish => sub {
         my ( $pid, $exitcode, $stdout, $stderr ) = @_;

         if( $exitcode != 0 ) {
            print STDERR $stderr;
            exit $exitcode;
         }

         print STDERR "Starting server for port $port\n";
         $self->add_child(
            $self->{proc} = IO::Async::Process->new(
               setup => [
                  chdir => $self->{synapse_dir},
               ],

               command => \@command,

               stderr => {
                  via => "pipe_read",
                  on_read => $self->_capture_weakself( 'on_synapse_read' ),
               },

               on_finish => $self->_capture_weakself( 'on_finish' ),
            )
         );
      }
   );
}

sub pid
{
   my $self = shift;
   return $self->{proc}->pid;
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

      $self->started_future->done if $line =~ m/INFO - Synapse now listening on port $self->{port}\s*$/;
   }

   return 0;
}

sub started_future
{
   my $self = shift;
   return $self->{started_future} ||= $self->loop->new_future;
}

1;
