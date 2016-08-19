return "SKIP" unless ($ENV{HOMESERVER}//"") eq "ruma";

my $N_HOMESERVERS = 2;

use SyTest::Homeserver::Ruma;

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
