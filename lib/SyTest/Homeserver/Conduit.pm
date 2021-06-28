package SyTest::Homeserver::Conduit;

use strict;
use warnings;
use 5.010;
use base qw( SyTest::Homeserver );

use Carp;

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
       binary
   );

   foreach (qw ( binary )) {
      defined $self->{$_} or croak "Need a $_";
   }

   $self->{port} = main::alloc_port( "conduit" );

   $self->SUPER::_init( $args );
}

sub configure
{
   my $self = shift;
   my %params = @_;

   $self->SUPER::configure( %params );
}

sub start
{
   my $self = shift;

   my $hs_dir = $self->{hs_dir};

   $self->{paths}{config} = $self->write_file( "conduit.toml" =>
"[global]
server_name = \"" . $self->server_name . "\"
database_path = \"$self->{hs_dir}/db\"
port = $self->{port}
max_request_size = 20_000_000
allow_registration = true
allow_federation = true
address = \"127.0.0.1\""
 );

   my $output = $self->{output};

   $output->diag( "Starting conduit server" );
   my @command = ( $self->{binary} );

   return $self->_start_process_and_await_connectable(
      setup => [
         env => {
            CONDUIT_CONFIG => "$self->{hs_dir}/conduit.toml",
         },
      ],
      command => [ @command ],
      connect_host => $self->{bind_host},
      connect_port => $self->{port},
   )->else( sub {
      die "Unable to start conduit: $_[0]\n";
   })->on_done( sub {
      $output->diag( "Started conduit server" );
   });
}

sub server_name
{
   my $self = shift;
   return $self->{bind_host} . ":" . $self->{port};
}

sub federation_host
{
   my $self = shift;
   return $self->{bind_host};
}

sub federation_port
{
   my $self = shift;
   return $self->{port};
}

sub public_baseurl
{
   my $self = shift;
   return "http://$self->{bind_host}:" . $self->{port};
}

1;
