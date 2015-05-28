package SyTest::Synapse;

use strict;
use warnings;
use 5.010;
use base qw( IO::Async::Notifier );

use IO::Async::Process;
use IO::Async::FileStream;

use Cwd qw( getcwd abs_path );
use File::Path qw( make_path );
use List::Util qw( any );

use YAML ();

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      port output synapse_dir extra_args python no_ssl
   );

   $self->SUPER::_init( $args );
}

sub configure
{
   my $self = shift;
   my %params = @_;

   exists $params{$_} and $self->{$_} = delete $params{$_} for qw(
      print_output filter_output
   );

   $self->SUPER::configure( %params );
}

sub _add_to_loop
{
   my $self = shift;
   my ( $loop ) = @_;

   my $port = $self->{port};
   my $output = $self->{output};

   my $hs_dir = abs_path("localhost-$port");
   -d $hs_dir or make_path $hs_dir;

   my $db_config_path = "$hs_dir/database.yaml";
   my $db  = ":memory:"; #"$hs_dir/homeserver.db";

   my ( $db_type, %db_args, $db_config );
   if( -f $db_config_path ) {
      $db_config = YAML::LoadFile( $db_config_path );
      if( $db_config->{name} eq "psycopg2") {
          $db_type = "pg";
          %db_args = %{ $db_config->{args} };
      }
      elsif ($db_config->{name} eq "sqlite3") {
          $db_type = "sqlite";
          $db_args{path} = $db_config->{args}->{database};
      }
      else {
         die "Unrecognised DB type '$db_config->{name}' in $db_config_path";
      }
   }
   else {
      $db_type = "sqlite";
      $db_args{path} = $db;
      $db_config = { name => "sqlite3", args => { database => $db } };
      YAML::DumpFile( $db_config_path, $db_config );
   }

   if( defined $db_type ) {
      $self->${\"clear_db_$db_type"}( %db_args );
   }

   my $cwd = getcwd;
   my $log = "$hs_dir/homeserver.log";

   my $conf = {
        "server_name" => "localhost:$port",
        "log_file" => "$log",
        "bind_port" => $port,
        ( $self->{no_ssl} ?
            ( "unsecure_port" => $port + 1000, ) :
            ( "unsecure_port" => 0 )),
        "tls-dh-params-path" => "$cwd/keys/tls.dh",
        "rc_messages_per_second" => 1000,
        "rc_message_burst_count" => 1000,
        "enable_registration" => "true",
        "database" => $db_config,
        "database_config" => $db_config_path,

        # Metrics are always useful
        "enable_metrics" => 1,
        "metrics_port" => ( $port - 8000 + 9090 ),
        "perspectives" => {servers => {}},
   };

   YAML::DumpFile("$hs_dir/config", $conf);


   $self->{logpath} = $log;

   {
      # create or truncate
      open my $tmph, ">", $log or die "Cannot open $log for writing - $!";
   }

   my $pythonpath = (
      exists $ENV{PYTHONPATH}
      ? "$self->{synapse_dir}:$ENV{PYTHONPATH}"
      : "$self->{synapse_dir}"
   );


   my @command = (
      $self->{python}, "-m", "synapse.app.homeserver",
         "--config-path" => "$hs_dir/config",
         "--server-name"   => "localhost:$port",
   );

   $output->diag( "Generating config for port $port" );

   $loop->run_child(
      setup => [
         env => {
            "PYTHONPATH" => $pythonpath,
            "PATH" => $ENV{PATH},
            "PYTHONDONTWRITEBYTECODE" => "Don't write .pyc files",
         },
      ],

      command => [ @command, "--generate-config" ],

      on_finish => sub {
         my ( $pid, $exitcode, $stdout, $stderr ) = @_;

         if( $exitcode != 0 ) {
            print STDERR $stderr;
            exit $exitcode;
         }

         $output->diag( "Starting server for port $port" );
         $self->add_child(
            $self->{proc} = IO::Async::Process->new(
               setup => [
                  env => {
                     "PYTHONPATH" => $pythonpath,
                     "PATH" => $ENV{PATH},
                     "PYTHONDONTWRITEBYTECODE" => "Don't write .pyc files",
                  },
               ],

               command => [ @command, @{ $self->{extra_args} } ],

               on_finish => $self->_capture_weakself( 'on_finish' ),
            )
         );

         $self->open_logfile;
      }
   );
}

sub pid
{
   my $self = shift;
   return $self->{proc}->pid;
}

sub kill
{
   my $self = shift;
   my ( $signal ) = @_;

   if( $self->{proc} and my $pid = $self->{proc}->pid ) {
      kill $signal => $pid;
   }
}

sub on_finish
{
   my $self = shift;
   my ( $process, $exitcode ) = @_;

   say $self->pid . " stopped";

   if( $exitcode > 0 ) {
      print STDERR "Process failed ($exitcode)\n";

      print STDERR "\e[1;35m[server $self->{port}]\e[m: $_\n"
         for @{ $self->{stderr_lines} // [] };

      # Now force all remaining output to be printed
      $self->{print_output}++;
      undef $self->{filter_output};
   }

   $self->await_finish->done( $exitcode );
}

sub open_logfile
{
   my $self = shift;

   $self->add_child(
      $self->{log_stream} = IO::Async::FileStream->new(
         filename => $self->{logpath},
         on_read => $self->_capture_weakself( 'on_synapse_read' ),
      )
   );
}

sub close_logfile
{
   my $self = shift;

   $self->remove_child( delete $self->{log_stream} );
}

sub on_synapse_read
{
   my $self = shift;
   my ( $stream, $bufref, $eof ) = @_;

   while( $$bufref =~ s/^(.*)\n// ) {
      my $line = $1;

      push @{ $self->{stderr_lines} }, $line;
      shift @{ $self->{stderr_lines} } while @{ $self->{stderr_lines} } > 20;

      if( $self->{print_output} ) {
         my $filter = $self->{filter_output};
         if( !$filter or any { $line =~ m/$_/ } @$filter ) {
            print STDERR "\e[1;35m[server $self->{port}]\e[m: $line\n";
         }
      }

      $self->started_future->done if $line =~ m/INFO .* Synapse now listening on port $self->{port}\s*$/;
   }

   return 0;
}

sub started_future
{
   my $self = shift;
   return $self->{started_future} ||= $self->loop->new_future;
}

sub await_finish
{
   my $self = shift;
   return $self->{finished_future} //= $self->loop->new_future;
}

sub print_output
{
   my $self = shift;
   my ( $on ) = @_;
   $on = 1 unless @_;

   $self->configure( print_output => $on );

   if( $on ) {
      print STDERR "\e[1;35m[server $self->{port}]\e[m: $_\n"
         for @{ $self->{stderr_lines} // [] };
   }

   undef @{ $self->{stderr_lines} };
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

   $self->{output}->diag( "Clearing Pg database $args{database} on $args{host}" );

   require DBI;
   require DBD::Pg;

   my $dbh = DBI->connect( "dbi:Pg:dbname=$args{database};host=$args{host}", $args{user}, $args{password} )
      or die DBI->errstr;

   foreach my $row ( @{ $dbh->selectall_arrayref( "SELECT tablename FROM pg_tables WHERE schemaname = 'public'" ) } ) {
      my ( $tablename ) = @$row;

      $dbh->do( "DROP TABLE $tablename CASCADE" ) or
         die $dbh->errstr;
   }
}

1;
