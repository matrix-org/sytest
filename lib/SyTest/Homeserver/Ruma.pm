package SyTest::Homeserver::Ruma;

use strict;
use warnings;
use 5.010;
use base qw( SyTest::Homeserver );

use Cwd qw( abs_path );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      ruma_dir db_args config
   );

   $self->SUPER::_init( $args );
}

sub start
{
   my $self = shift;

   my $hs_dir = $self->{hs_dir};
   -d $hs_dir or mkdir $hs_dir;

   my $db_args = $self->{db_args};

   $self->{config}{postgres_url} //= sprintf( "postgres://%s:%s@%s/%s",
      $db_args->{user}, $db_args->{password}, $db_args->{host}, "ruma"
   ),

   $self->write_json_file( "ruma.json", $self->{config} );

   my $ruma = abs_path( "$self->{ruma_dir}/target/debug/ruma" );

   $self->clear_db_pg(
      host     => $db_args->{host},
      database => "ruma",
      user     => $db_args->{user},
      password => $db_args->{database},
   );

   # ruma itself wants the 'migrations' directory which contains its database
   # schemata
   symlink abs_path( "$self->{ruma_dir}/migrations" ), "migrations";

   my $loop = $self->loop;

   $self->add_child(
      $self->{proc} = IO::Async::Process->new(
         setup => [ chdir => $hs_dir ],

         command => [ $ruma, "run" ],

         on_finish => sub {
            my ( $pid, $exitcode, $stdout, $stderr ) = @_;

            print STDERR "\n\n-----------------" .
               "\n\n\nRUMA died($exitcode)\n$stdout\n$stderr\n\n--------------".
               "\n\n";
         },
      )
   );
}

sub kill
{
   my $self = shift;
   my ( $signal ) = @_;

   if( $self->{proc} and my $pid = $self->{proc}->pid ) {
      kill $signal => $pid;
   }
}

1;
