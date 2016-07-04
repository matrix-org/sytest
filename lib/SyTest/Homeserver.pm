package SyTest::Homeserver;

use strict;
use warnings;
use 5.010;
use base qw( IO::Async::Notifier );

use YAML ();

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

1;
