package SyTest::Homeserver;

use strict;
use warnings;
use 5.010;
use base qw( IO::Async::Notifier );

use Future::Utils qw( repeat );

use YAML ();
use JSON ();
use File::Slurper qw( write_binary );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      output hs_dir
   );

   $self->SUPER::_init( $args );
}

sub write_yaml_file
{
   my $self = shift;
   my ( $relpath, $content ) = @_;

   my $hs_dir = $self->{hs_dir};

   YAML::DumpFile( my $abspath = "$hs_dir/$relpath", $content );

   return $abspath;
}

sub write_json_file
{
   my $self = shift;
   my ( $relpath, $content ) = @_;

   my $hs_dir = $self->{hs_dir};

   write_binary( my $abspath = "$hs_dir/$relpath", JSON::encode_json( $content ) );

   return $abspath;
}

sub clear_db_sqlite
{
   my $self = shift;
   my %args = @_;

   my $db = $args{path};

   $self->{output}->diag( "Clearing SQLite database at $db" );

   unlink $db if -f $db;
}

sub clear_db_pg
{
   my $self = shift;
   my %args = @_;

   my $host = $args{host} // '';
   $self->{output}->diag( "Clearing Pg database $args{database} on '$host'" );

   require DBI;
   require DBD::Pg;

   my $dbh = DBI->connect( "dbi:Pg:dbname=$args{database};host=$host", $args{user}, $args{password} )
      or die DBI->errstr;

   foreach my $row ( @{ $dbh->selectall_arrayref( "SELECT tablename FROM pg_tables WHERE schemaname = 'public'" ) } ) {
      my ( $tablename ) = @$row;

      $dbh->do( "DROP TABLE $tablename CASCADE" ) or
         die $dbh->errstr;
   }
}

sub await_connectable
{
   my $self = shift;
   my ( $port ) = @_;

   my $loop = $self->loop;

   my $attempts = 20;

   repeat {
      $loop->connect(
         addr => {
            family   => "inet",
            socktype => "stream",
            port     => $port,
            ip       => "127.0.0.1",
         }
      )->then_done(1)
       ->else( sub {
         if( !$attempts ) {
            return Future->fail( "Failed to connect to $port" )
         }

         $attempts--;

         $loop->delay_future( after => 0.1 )
              ->then_done(0);
      })
   } while => sub { !$_[0]->failure and !$_[0]->get }
}

1;
