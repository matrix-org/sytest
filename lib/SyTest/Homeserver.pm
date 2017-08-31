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

=head1 NAME

C<SyTest::Homeserver> - base class for homeserver implementations

=head1 DESCRIPTION

This class forms the basis for the various classes which implement homeservers
(or, more accurately, which provide the code to configure, start, and stop
homeserver implementations).

=head1 REQUIRED PARAMETERS

The following named parameters must be passed to C<new>:

=head2 output => SyTest::Output

An Output instance which is used to write diagnostic information.

=head2 hs_dir => STRING

A path unique to this homeserver instance, which will be created as a temporary
directory to hold things like config files and logs.

=head2 hs_index => INTEGER

The index of this homeserver (starting from 0). Used to identify it in
diagnostic messages etc.

=head1 SUBCLASS METHODS

The folowing methods must be provided by any subclass which implements the
Homeserver interface.

=head2 secure_port

   $hs->secure_port

This method should return the port number where the homeserver exposes a
client-server API over HTTPS.

=head2 unsecure_port

   $hs->unsecure_port

This method should return the port number where the homeserver exposes a
client-server API over HTTP.

=cut

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

=head1 UTILITY METHODS

=cut

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

=head2 _get_dbconfig

   %db_config = $self->_get_dbconfig( %defaults )

This method loads the database config from C<database.yaml>, or creates that
file according to the given defaults.

It then passes the loaded config to C<_check_db_config> for
sanity-checking. That method may be overridden by subclasses, and should C<die>
if there is a problem with the config.

Finally, it calls the relevant clear_db method to clear out the configured
database.

It returns the config hash.

=cut

sub _get_dbconfig
{
   my $self = shift;
   my ( %defaults ) = @_;

   my $hs_dir = $self->{hs_dir};
   my $db_config_path = "database.yaml";
   my $db_config_abs_path = "$hs_dir/${db_config_path}";

   my ( %db_config );
   if( -f $db_config_abs_path ) {
      %db_config = %{ YAML::LoadFile( $db_config_abs_path ) };

      # backwards-compatibility hacks
      my $db_name = delete $db_config{name};
      if( defined $db_name ) {
         if( $db_name eq 'psycopg2' ) {
            $db_config{type} = 'pg';
         }
         elsif( $db_name eq 'sqlite3' ) {
            $db_config{type} = 'sqlite';
         }
         else {
            die "Unrecognised DB name '$db_name' in $db_config_abs_path";
         }
      }
   }
   else {
      YAML::DumpFile( $db_config_abs_path, \%defaults );
      %db_config = %defaults;
   }

   eval {
      $self->_check_db_config( %db_config );
      1;
   } or die "Error loading db config $db_config_abs_path: $@";

   my $db_type = $db_config{type};
   my $clear_meth = "_clear_db_${db_type}";
   $self->$clear_meth( %{ $db_config{args} } );

   return %db_config;
}

sub _check_db_config
{
   my $self = shift;
   my ( %db_config ) = @_;

   my $db_type = $db_config{type};
   if( $db_type eq 'pg' ) {
      foreach (qw( database host user password )) {
         if( !$db_config{args}->{$_} ) {
            die "Missing required database argument $_";
         }
      }
   }
   elsif( $db_type eq 'sqlite' ) {
      foreach (qw( database )) {
         if( !$db_config{args}->{$_} ) {
            die "Missing required database argument $_";
         }
      }
   }
   else {
      die "Unrecognised DB type '$db_type'";
   }
}

sub _clear_db_sqlite
{
   my $self = shift;
   my %args = @_;

   my $db = $args{database};

   $self->{output}->diag( "Clearing SQLite database at $db" );

   unlink $db if -f $db;
}

sub _clear_db_pg
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

   my $output = $self->{output};

   $output->diag( "Connecting to server $port" );

   my $fut = repeat {
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
   } while => sub { !$_[0]->failure and !$_[0]->get };

   $fut->on_done( sub {
      $output->diag( "Connected to server $port" );
   });

   return $fut;
}

1;
