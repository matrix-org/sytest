package SyTest::Synapse;

use strict;
use warnings;
use 5.010;
use base qw( IO::Async::Notifier );

use Future::Utils qw( try_repeat );

use IO::Async::Process;
use IO::Async::FileStream;

use Cwd qw( getcwd abs_path );
use File::Basename qw( dirname );
use File::Path qw( make_path remove_tree );
use List::Util qw( any );
use POSIX qw( strftime );

use YAML ();

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      port unsecure_port output synapse_dir extra_args python config coverage
      dendron
   );

   $self->{hs_dir} = abs_path( "localhost-$self->{port}" );

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

sub _append
{
   my ( $config, $more ) = @_;
   if( ref $more eq "HASH" ) {
      ref $config eq "HASH" or die "Cannot append HASH to non-HASH";
      _append( $_[0]->{$_}, $more->{$_} ) for keys %$more;
   }
   elsif( ref $more eq "ARRAY" ) {
      push @{ $_[0] }, @$more;
   }
   else {
      die "Not sure how to append ${\ref $more} to config\n";
   }
}

sub append_config
{
   my $self = shift;
   my %more = @_;

   _append( $self->{config}, \%more );
}

sub write_yaml_file
{
   my $self = shift;
   my ( $relpath, $content ) = @_;

   my $hs_dir = $self->{hs_dir};
   -d $hs_dir or make_path $hs_dir;

   YAML::DumpFile( my $abspath = "$hs_dir/$relpath", $content );

   return $abspath;
}

sub start
{
   my $self = shift;

   my $port = $self->{port};
   my $output = $self->{output};

   my $db_config_path = "database.yaml";
   my $db_config_abs_path = "$self->{hs_dir}/${db_config_path}";
   my $db  = ":memory:"; #"$hs_dir/homeserver.db";

   my ( $db_type, %db_args, $db_config );
   if( -f $db_config_abs_path ) {
      $db_config = YAML::LoadFile( $db_config_abs_path );
      if( $db_config->{name} eq "psycopg2") {
          $db_type = "pg";
          %db_args = %{ $db_config->{args} };
      }
      elsif ($db_config->{name} eq "sqlite3") {
          $db_type = "sqlite";
          $db_args{path} = $db_config->{args}->{database};
      }
      else {
         die "Unrecognised DB type '$db_config->{name}' in $db_config_abs_path";
      }
   }
   else {
      $db_type = "sqlite";
      $db_args{path} = $db;
      $db_config = { name => "sqlite3", args => { database => $db } };
      $self->write_yaml_file( $db_config_path, $db_config );
   }

   if( defined $db_type ) {
      $self->${\"clear_db_$db_type"}( %db_args );
   }

   # Clean up the media_store directory each time, or else it fills up with
   # thousands of automatically-generated avatar images
   if( -d "media_store" ) {
      remove_tree( "media_store" );
   }

   my $cwd = getcwd;
   my $log = "$self->{hs_dir}/homeserver.log";

   my $listeners = [];

   if( $self->{dendron} ) {
      # If we are running synapse behind dendron then only bind the unsecure
      # port for synapse.
      $self->{unsecure_port} = $port + 9000 - 8000;
   }
   else {
      push @$listeners, {
         type => "http",
         port => $port,
         bind_address => "127.0.0.1",
         tls => 1,
         resources => [{
            names => [ "client", "federation" ], compress => 0
         }]
      };
   }

   if( $self->{unsecure_port} ) {
      push @$listeners, {
         type => "http",
         port => $self->{unsecure_port},
         bind_address => "127.0.0.1",
         tls => 0,
         resources => [{
            names => [ "client", "federation" ], compress => 0
         }]
      }
   }

   my $cert_file = "$self->{hs_dir}/cert.pem";
   my $key_file = "$self->{hs_dir}/key.pem";

   my $macaroon_secret_key = "secret_$self->{port}";

   my $config_path = $self->write_yaml_file( config => {
        "server_name" => "localhost:$port",
        "log_file" => "$log",
        "tls_certificate_path" => $cert_file,
        "tls_private_key_path" => $key_file,
        "tls_dh_params_path" => "$cwd/keys/tls.dh",
        "rc_messages_per_second" => 1000,
        "rc_message_burst_count" => 1000,
        "enable_registration" => "true",
        "database" => $db_config,
        "database_config" => $db_config_path,
        "macaroon_secret_key" => $macaroon_secret_key,

        # Metrics are always useful
        "enable_metrics" => 1,
        "metrics_port" => ( $port - 8000 + 9090 ),

        "perspectives" => { servers => {} },

        # Stack traces are useful
        "full_twisted_stacktraces" => "true",

        "listeners" => $listeners,

        "bcrypt_rounds" => 0,

        %{ $self->{config} },
   } );

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

   my @synapse_command = ( $self->{python} );

   if( $self->{coverage} ) {
      # Ensures that even --generate-config has coverage reports. This is intentional
      push @synapse_command,
         "-m", "coverage", "run", "-p", "--source=$self->{synapse_dir}/synapse";
   }

   push @synapse_command,
      "-m", "synapse.app.homeserver",
      "--config-path" => $config_path,
      "--server-name" => "localhost:$port";

   $output->diag( "Generating config for port $port" );

   my @config_command = (
      @synapse_command, "--generate-config", "--report-stats=no"
   );

   my @command;

   if( $self->{dendron} ) {
      $db_type eq "pg" or die "Dendron can only run against postgres";

      my @db_arg_pairs = ();
      while( my ( $key, $value ) = each %db_args ) {
         if ( $key eq "database" ) {
            $key = "dbname";
         }
         push @db_arg_pairs, $key . '=' . $value;
      }

      @command = (
         $self->{dendron},
         "--synapse-python" => $self->{python},
         "--synapse-config" => $config_path,
         "--synapse-url" => "http://127.0.0.1:$self->{unsecure_port}",
         "--synapse-postgres" => join(" ", @db_arg_pairs),
         "--macaroon-secret" => $macaroon_secret_key,
         "--server-name" => "localhost:$port",
         "--cert-file" => $cert_file,
         "--key-file" => $key_file,
         "--addr" => "127.0.0.1:$port",
      )
   }
   else {
      @command = @synapse_command
   }

   my $env = {
      "PYTHONPATH" => $pythonpath,
      "PATH" => $ENV{PATH},
      "PYTHONDONTWRITEBYTECODE" => "Don't write .pyc files",
   };

   my $loop = $self->loop;
   $loop->run_child(
      setup => [ env => $env ],

      command => [ @config_command ],

      on_finish => sub {
         my ( $pid, $exitcode, $stdout, $stderr ) = @_;

         if( $exitcode != 0 ) {
            print STDERR $stderr;
            exit $exitcode;
         }

         $output->diag( "Starting server for port $port" );
         $self->add_child(
            $self->{proc} = IO::Async::Process->new(
               setup => [ env => $env ],

               command => [ @command, @{ $self->{extra_args} } ],

               on_finish => $self->_capture_weakself( 'on_finish' ),
            )
         );

         my $polling_period = 0.01;
         my $polling_count = 20;
         my $poll;
         $poll = sub {
            print STDERR "Connecting to server $self->{port}\n";
            $loop->connect(
               addr => {
                  family   => "inet",
                  socktype => "stream",
                  port     => $self->{port},
                  ip       => "127.0.0.1",
               }
            )->then( sub {
               print STDERR "Connected to server $self->{port}\n";
               my ( $connection ) = @_;

               $connection->close;

               $self->started_future->done;
            }, sub {
               $polling_period *= 2;
               $polling_count -= 1;

               if ( $polling_count == 0 ) {
                  die "Synapse failed to start within ${polling_period}s";
               }

               $loop->delay_future( after => $polling_period )->then( $poll );
            });
         };

         $self->adopt_future( $poll->() );

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

sub rotate_logfile
{
   my $self = shift;
   my ( $newname ) = @_;

   my $logpath = $self->{logpath};

   $newname //= dirname( $logpath ) . strftime( "/homeserver-%Y-%m-%dT%H:%M:%S.log", localtime );

   rename( $logpath, $newname );

   $self->kill( 'HUP' );

   try_repeat {
      -f $logpath and return Future->done(1);

      $self->loop->delay_future( after => 0.5 )->then_done(0);
   } foreach => [ 1 .. 20 ],
     while => sub { !shift->get },
     otherwise => sub { die "Timed out waiting for synapse to recreate its log file" };
}

1;
