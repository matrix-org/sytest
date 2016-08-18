return "SKIP" unless ($ENV{HOMESERVER}//"") eq "ruma";

my $N_HOMESERVERS = 2;

use Cwd qw( abs_path );

my @rumas;

# Almost like an END block, but we can't use END because we need SIGCHLD, and
# see
#   https://rt.perl.org/Public/Bug/Display.html?id=128774
main::AT_END sub {
   $OUTPUT->diag( "Killing ruma servers" ) if @rumas;

   foreach my $ruma ( values @rumas ) {
      $ruma->kill( 'INT' );
   }
};

push our @EXPORT, qw( HOMESERVER_INFO );

our @HOMESERVER_INFO = map {
   my $idx = $_;

   fixture(
      requires => [],

      setup => sub {

         my $port = main::alloc_port( "ruma[$idx]" );

         my $location = "http://localhost:$port";

         my $info = ServerInfo( "localhost:$port", $location );

         my $db_config = YAML::LoadFile( "database.yaml" );
         my %db_args = %{ $db_config->{args} };

         my $ruma = SyTest::Homeserver::Ruma->new(
            ruma_dir => "../ruma",
            hs_dir   => abs_path( "localhost-$idx" ),

            output => $OUTPUT,

            config => {
               domain              => "localhost:$port",
               bind_port           => $port,
               macaroon_secret_key => "PBHIVfqSM5q8/jyameDVcxFhJrSEVxmyVggN/9dW0N4=",
               postgres_url        => sprintf( "postgres://%s:%s@%s/%s",
                  $db_args{user}, $db_args{password}, $db_args{host}, "ruma" ),
            },
         );
         $loop->add( $ruma );

         push @rumas, $ruma;

         $ruma->start;

         $loop->delay_future( after => 2 )->then( sub {
            Future->done( $info );
         });
      },
   );
} 0 .. $N_HOMESERVERS-1;

package SyTest::Homeserver::Ruma;
use base qw( SyTest::Homeserver );

use Cwd qw( abs_path );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      ruma_dir config
   );

   $self->SUPER::_init( $args );
}

sub start
{
   my $self = shift;

   my $hs_dir = $self->{hs_dir};
   -d $hs_dir or mkdir $hs_dir;

   $self->write_json_file( "ruma.json", $self->{config} );

   my $ruma = abs_path( "$self->{ruma_dir}/target/debug/ruma" );

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
