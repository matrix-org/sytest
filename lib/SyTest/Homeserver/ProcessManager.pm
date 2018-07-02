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

=head1 NAME

C<SyTest::Homeserver::ProcessManager>

=head1 DESCRIPTION

This class is a mixin for C<SyTest::Homeserver> implementations (or, in fact,
any C<IO::Async::Notifier> class) which start external processes.

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

   my $proc_info = ProcessInfo( undef, $fut, [], 1 );

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
      $self->await_connectable( $self->{bind_host}, $self->secure_port ),
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

1;

