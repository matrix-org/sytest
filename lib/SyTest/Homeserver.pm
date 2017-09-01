package SyTest::Homeserver;

use strict;
use warnings;
use 5.010;
use base qw( IO::Async::Notifier );

use Future::Utils qw( repeat );

use YAML ();
use JSON ();
use File::Path qw( make_path );
use File::Slurper qw( write_binary );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      output hs_dir
   );

   my $hs_dir = $self->{hs_dir};
   -d $hs_dir or make_path $hs_dir;

   $self->SUPER::_init( $args );
}

sub write_file
{
   my $self = shift;
   my ( $relpath, $content ) = @_;

   my $hs_dir = $self->{hs_dir};

   write_binary( my $abspath = "$hs_dir/$relpath", $content );

   return $abspath;
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

   return $self->write_file( $relpath, JSON::encode_json( $content ) );
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

   # If there is a DB called sytest_template use that as the template for the
   # sytest databases. Otherwise initialise the DB from scratch (which can take
   # a fair few seconds)
   my $dbh = DBI->connect( "dbi:Pg:dbname=sytest_template;host=$host", $args{user}, $args{password} );
   if ( $dbh ) {
      $dbh->do( "DROP DATABASE $args{database}" );  # we don't mind if this dies

      $dbh->do( "CREATE DATABASE $args{database} WITH TEMPLATE sytest_template" ) or
         die $dbh->errstr;
   }
   else {
      $dbh = DBI->connect( "dbi:Pg:dbname=$args{database};host=$host", $args{user}, $args{password} )
         or die DBI->errstr;

      foreach my $row ( @{ $dbh->selectall_arrayref( "SELECT tablename FROM pg_tables WHERE schemaname = 'public'" ) } ) {
         my ( $tablename ) = @$row;

         $dbh->do( "DROP TABLE $tablename CASCADE" ) or
            die $dbh->errstr;
      }
   }
}

sub await_connectable
{
   my $self = shift;
   my ( $host, $port ) = @_;

   my $loop = $self->loop;

   my $attempts = 25;
   my $delay    = 0.05;

   repeat {
      $loop->connect(
         host     => $host,
         service  => $port,
         socktype => "stream",
      )->then_done(1)
       ->else( sub {
         if( !$attempts ) {
            return Future->fail( "Failed to connect to $port" )
         }

         $attempts--;
         $delay *= 1.3;

         $loop->delay_future( after => $delay )
              ->then_done(0);
      })
   } while => sub { !$_[0]->failure and !$_[0]->get }
}

1;
