package SyTest::Synapse;

use strict;
use warnings;
use 5.010;
use base qw( IO::Async::Notifier );

use IO::Async::Process;

use File::chdir;
use File::Path qw( make_path );
use List::Util qw( any );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      port output synapse_dir extra_args python no_ssl
   );

   $self->SUPER::_init( $args );
}

sub configure
{
   my $self = shift;
   my %params = @_;

   exists $params{$_} and $self->{$_} = delete $params{$_} for qw(
      print_output filter_output
   );

   $self->SUPER::configure( %params );
}

sub _add_to_loop
{
   my $self = shift;
   my ( $loop ) = @_;

   my $port = $self->{port};
   my $output = $self->{output};

   my $hs_dir = "localhost-$port";
   my $db = "$hs_dir/homeserver.db";

   {
      -d $hs_dir or make_path $hs_dir;
      unlink $db if -f $db;
   }

   my $pythonpath = (
      exists $ENV{PYTHONPATH}
      ? "$self->{synapse_dir}:$ENV{PYTHONPATH}"
      : "$self->{synapse_dir}"
   );

   my @command = (
      $self->{python}, "-m", "synapse.app.homeserver",
         "--config-path" => "$hs_dir/config",
         "--log-file"    => "",

         "--server-name"   => "localhost:$port",
         "--bind-port"     => $port,
         "--database-path" => $db,
         "--manhole"       => $port - 1000,

         ( $self->{no_ssl} ?
            ( "--unsecure-port" => $port + 1000, ) :

            ( "--unsecure-port" => 0 ) ),

         # TLS parameters
         "--tls-dh-params-path" => "$CWD/keys/tls.dh",

         # Allow huge amounts of messages before burst rate kicks in
         "--rc-messages-per-second" => 1000,
         "--rc-message-burst-count" => 1000,

         "--enable-registration" => 1,
   );

   $output->diag( "Generating config for port $port" );

   $loop->run_child(
      setup => [
         env => {
            "PYTHONPATH" => $pythonpath,
            "PATH" => $ENV{PATH},
            "PYTHONDONTWRITEBYTECODE" => "Don't write .pyc files",
         },
      ],

      command => [ @command, "--generate-config" ],

      on_finish => sub {
         my ( $pid, $exitcode, $stdout, $stderr ) = @_;

         if( $exitcode != 0 ) {
            print STDERR $stderr;
            exit $exitcode;
         }

         $output->diag( "Starting server for port $port" );
         $self->add_child(
            $self->{proc} = IO::Async::Process->new(
               setup => [
                  env => {
                     "PYTHONPATH" => $pythonpath,
                     "PATH" => $ENV{PATH},
                     "PYTHONDONTWRITEBYTECODE" => "Don't write .pyc files",
                  },
               ],

               command => [ @command, @{ $self->{extra_args} } ],

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

sub kill
{
   my $self = shift;
   my ( $signal ) = @_;

   if( $self->{proc} and my $pid = $self->{proc}->pid ) {
      kill $signal => $pid;
   }
}

sub on_finish
{
   my $self = shift;
   my ( $process, $exitcode ) = @_;

   say $self->pid . " stopped";

   if( $exitcode > 0 ) {
      print STDERR "Process failed ($exitcode)\n";

      print STDERR "\e[1;35m[server $self->{port}]\e[m: $_\n"
         for @{ $self->{stderr_lines} // [] };

      # Now force all remaining output to be printed
      $self->{print_output}++;
      undef $self->{filter_output};
   }

   $self->await_finish->done( $exitcode );
}

sub on_synapse_read
{
   my $self = shift;
   my ( $proc, $bufref, $eof ) = @_;

   while( $$bufref =~ s/^(.*)\n// ) {
      my $line = $1;

      push @{ $self->{stderr_lines} }, $line;
      shift @{ $self->{stderr_lines} } while @{ $self->{stderr_lines} } > 20;

      if( $self->{print_output} ) {
         my $filter = $self->{filter_output};
         if( !$filter or any { $line =~ m/$_/ } @$filter ) {
            print STDERR "\e[1;35m[server $self->{port}]\e[m: $line\n";
         }
      }

      $self->started_future->done if $line =~ m/INFO .* Synapse now listening on port $self->{port}\s*$/;
   }

   return 0;
}

sub started_future
{
   my $self = shift;
   return $self->{started_future} ||= $self->loop->new_future;
}

sub await_finish
{
   my $self = shift;
   return $self->{finished_future} //= $self->loop->new_future;
}

sub print_output
{
   my $self = shift;
   my ( $on ) = @_;
   $on = 1 unless @_;

   $self->configure( print_output => $on );

   if( $on ) {
      print STDERR "\e[1;35m[server $self->{port}]\e[m: $_\n"
         for @{ $self->{stderr_lines} // [] };
   }

   undef @{ $self->{stderr_lines} };
}

1;
