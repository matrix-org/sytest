package SyTest::TCPProxy;

use strict;
use warnings;
use Carp;

# A subclass of IO:Async::Listener that forwards all of its connections
# to another TCP socket

use base qw( IO::Async::Listener );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      output
   );

   $self->SUPER::_init( $args );
}

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( host port )) {
      $self->{$_} = delete $params{$_} if $params{$_};
   }
   
   $self->SUPER::configure( %params );
}

sub on_stream
{
   my $self = shift;

   my ( $incoming ) = @_;

   my $socket1 = $incoming->read_handle;
   my $peeraddr = $socket1->peerhost . ":" . $socket1->peerport;

   $self->{output}->diag("connection to proxy server from $peeraddr");

   my ($host, $port) = ($self->{'host'}, $self->{'port'});
   
   my $fut = $self->loop->connect(
      host => $host,
      service => $port,
      socktype => "stream",

      on_stream => sub {
         my ( $outgoing ) = @_;
         
         $self->{output}->diag("connected to $host:$port");

         $outgoing->configure(
            on_read => sub {
               my ( $self, $buffref, $eof ) = @_;
               $incoming->write( $$buffref );
               $$buffref = "";
               return 0;
            },
            on_closed => sub {
               $incoming->close_when_empty;
            },
         );

         $incoming->configure(
            on_read => sub {
               my ( $self, $buffref, $eof ) = @_;
               $outgoing->write( $$buffref );
               $$buffref = "";
               return 0;
            },
            on_closed => sub {
               $outgoing->close();
            },
         );
         
         $self->loop->add( $incoming );
         $self->loop->add( $outgoing );
      },
   );

   $self->adopt_future($fut);
}

1;
