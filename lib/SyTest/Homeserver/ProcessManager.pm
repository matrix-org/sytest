# Copyright 2017 New Vector Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use Future;

package SyTest::Homeserver::ProcessManager;

use Future::Utils qw( fmap_void );
use POSIX qw( WIFEXITED WEXITSTATUS );
use Struct::Dumb;
use IO::Async::Socket;

=head1 NAME

C<SyTest::Homeserver::ProcessManager>

=head1 DESCRIPTION

This class is a mixin for C<IO::Async::Notifier> classes which start external processes.

=cut

struct ProcessInfo => [qw( process finished_future output_lines print_output )];

=head1 UTILITY METHODS

=head2 _start_process

   $proc = $hs->_start_process( %params )

This method starts a new IO::Async::Process which will be killed/waited for by
C<kill_and_await_finish>.

The paramters may include:

=over

=item command => ARRAY

Passed to C<IO::Async::Process::new>, giving the command to be run.

=item setup => ARRAY

Optional reference to an array to pass to the underlying C<Loop>
C<spawn_child> method.

=back

It returns the Process object.

=cut

sub _start_process
{
   my $self = shift;
   my %params = @_;
   my %process_params = ();

   foreach (qw( command setup )) {
      $process_params{$_} = delete $params{$_}
         if exists $params{$_};
   }

   $self->{proc_info} //= {};

   my $fut = $self->loop->new_future;

   my $proc_info = ProcessInfo( undef, $fut, [], 0 );

   my $on_output = sub {
      my ( $stream, $buffref, $eof ) = @_;
      while ( $$buffref =~ s/^(.*)\n// ) {
         $self -> _on_output_line( $proc_info, $1 );
      }
      return 0;
   };

   my $proc = IO::Async::Process->new(
      %process_params,
      stdout => { on_read => $on_output },
      stderr => { on_read => $on_output },
      on_finish => $self->_capture_weakself( '_on_finish' ),
   );

   $self->add_child($proc);
   $proc_info->process = $proc;
   $self->{proc_info}{$proc} = $proc_info;
   return $proc;
}

# helper for _start_process
sub _on_output_line
{
   my $self = shift;
   my ( $proc_info, $line ) = @_;

   push @{ $proc_info->output_lines }, $line;
   shift @{ $proc_info->output_lines } while @{ $proc_info->output_lines } > 20;

   if( $proc_info->print_output ) {
      print STDERR "\e[1;35m[server]\e[m: $line\n";
   }
}

# helper for _start_process
sub _on_finish
{
   my $self = shift;
   my ( $process, $exitcode ) = @_;

   if( $exitcode > 0 ) {
      if( WIFEXITED($exitcode) ) {
         warn "Homeserver process exited " . WEXITSTATUS($exitcode) . "\n";
      }
      else {
         warn "Homeserver process failed - code=$exitcode\n";
      }
   }

   my $proc_info = $self->{proc_info}{$process};

   # print the last few lines of output
   print STDERR "\e[1;35m[server]\e[m: $_\n"
      for @{ $proc_info->output_lines };

   # - and force anything that has yet to hit the buffer to be printed
   $proc_info->print_output = 1;

   $proc_info->finished_future->done( $exitcode );
}


=head2 _start_process_and_await_connectable

   $started_future = $hs->_start_process_and_await_connectable( %params )

This method starts a new process, and then waits until we can connect to a
given TCP port.

The following parameters must be given:

=over

=item C<connect_host>

=item C<connect_port>

The host and port to connect to, to determine if the process is ready.

=back

Other parameters are passed on to C<IO::Async::Process::new>.

=cut

sub _start_process_and_await_connectable
{
   my $self = shift;
   my %params = @_;

   my $connect_host = delete $params{connect_host};
   my $connect_port = delete $params{connect_port};

   my $proc = $self -> _start_process( %params );
   my $finished_future = $self->{proc_info}{$proc}->finished_future;

   my $fut = Future->wait_any(
      $self->await_connectable( $connect_host, $connect_port ),
      $finished_future->without_cancel()->then_fail(
         "Process died without becoming connectable",
      ),
   );
   return $fut;
}

=head2 kill_and_await_finish

   $fut = $hs->kill_and_await_finish()

This method kills all of our processes and returns a future which will resolve
once all of them have exited.

=cut

sub kill_and_await_finish
{
   my $self = shift;

   my @proc_infos = values ( %{ $self->{proc_info} // {} } );

   return fmap_void(
      sub {
         my ( $proc_info ) = @_;
         return $self->_kill_process( $proc_info );
      },
      foreach => \@proc_infos,
      concurrent => 10,
   );
}

# kill a single process and wait for it to exit
sub _kill_process
{
   my $self = shift;
   my ( $proc_info ) = @_;
   my $process = $proc_info->process;

   if( ! $process->is_running ) {
      return Future->done;
   }

   my $finished_future = $proc_info->finished_future;

   $self->{output}->diag( "Killing process " . $process->pid );
   $process->kill( 'INT' );
   return Future->needs_any(
      $finished_future->without_cancel,

      $self->loop->delay_future( after => 30 )->then( sub {
         $self->{output}->diag( "Timed out waiting for ${\ $process->pid }; sending SIGKILL" );
         $process->kill( 'KILL' );
         Future->done;
      }),
   );
}

=head2 _start_process_and_await_notify

   $fut = $hs->_start_process_and_await_notify( %params )

This method starts a new process, setting the `NOTIFY_SOCKET` env, and waits to
receive a `READY=1` notification from the process on the socket.

Parameters are passed on to C<IO::Async::Process::new>.

=cut

sub _start_process_and_await_notify
{
   my $self = shift;

   my %params = @_;

   # We now need to do some faffing to pull out any passed env hash so that we
   # can then pass it to `_await_ready_notification`.
   #
   # The env is passed in as part of the `setup` param, which is an ordered map
   # represented as an array.
   $params{setup} //= [];

   my $setup = $params{setup};

   my %setup_map = @$setup;  # Copy to a hash so we can pull out the env entry.
   my $env = $setup_map{env} // {};
   if ( not defined $setup_map{env} ) {
      # There was no env entry, so we me need to add it to the setup array.
      push @$setup, env => $env;
   }

   # We need to set this up *before* we start the process as we need to bind the
   # socket before startin the process.
   my $await_fut = $self->_await_ready_notification( $env );

   my $proc = $self -> _start_process( %params );
   my $finished_future = $self->{proc_info}{$proc}->finished_future;

   my $fut = Future->wait_any(
      $await_fut,
      $finished_future->without_cancel()->then_fail(
         "Process died without becoming connectable",
      ),
   )->else_with_f( sub {
      my ( $f ) = @_;

      # We need to manually kill child procs here as we don't seem to have
      # registered the on finish handler yet.
      $self->kill_and_await_finish()->then( sub {
         $f
      })
   } );
   return $fut;
}

=head2 _await_ready_notification

   $fut = $hs->_await_ready_notification( $env )

This method binds a listener to a newly created unix socket and waits for a
`READY=1` to be received. The socket address is added to the `env` map passed
in under `NOTIFY_SOCKET`.

This is basically a noddy implementation of the `sd_notify` mechanism.

=cut

sub _await_ready_notification
{
   my $self = shift;

   my ( $env ) = @_;

   my $loop = $self->loop;
   my $output = $self->{output};

   # Create a random abstract socket name. Abstract sockets start with a null
   # byte.
   my $random_id = join "", map { chr 65 + rand 25 } 1 .. 20;
   my $path = "\0sytest-$random_id.sock";

   # We replace null byte with '@' to allow us to pass it in via env. (This is
   # as per the sd_notify spec).
   $env->{"NOTIFY_SOCKET"} = $path =~ s/\0/\@/rg;

   # Create a future that gets resolved when we receive a `READY=1`
   # notification.
   my $poke_fut = Future->new;

   my $socket = IO::Async::Socket->new(
      on_recv => sub {
         my ( $self, $dgram, $addr ) = @_;

         # Payloads are newline separated list of varalbe assignments.
         foreach my $line ( split(/\n/, $dgram) ) {
            $output->diag( "Received signal from process: $line" );
            if ( $line eq "READY=1" ) {
               $poke_fut->done;
            }
         }

         $loop->stop;
      },
      on_recv_error => sub {
         my ( $self, $errno ) = @_;
         die "Cannot recv - $errno\n";
      },
   );
   $loop->add( $socket );

   $socket->bind( {
      family   => "unix",
      socktype => "dgram",
      path     => $path,
   } )->then( sub {
      # We add a timeout so that we don't wait for ever if process wedges.
      Future->wait_any(
         $poke_fut,
         $loop->timeout_future( after => 15 )
      )
   })
}

1;
