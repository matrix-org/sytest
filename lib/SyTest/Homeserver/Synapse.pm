package SyTest::Homeserver::Synapse;

use strict;
use warnings;
use 5.010;
use base qw( SyTest::Homeserver );

use Carp;

use Future::Utils qw( try_repeat );

use IO::Async::Process;
use IO::Async::FileStream;

use Cwd qw( getcwd );
use File::Basename qw( dirname );
use File::Path qw( remove_tree );
use List::Util qw( any );
use POSIX qw( strftime WIFEXITED WEXITSTATUS );

use YAML ();

sub new
{
   my $class = shift;
   my %args = @_;

   if( delete $args{haproxy} ) {
      $class = "SyTest::Homeserver::Synapse::ViaHaproxy";
   }
   elsif( $args{dendron} ) {
      $class = "SyTest::Homeserver::Synapse::ViaDendron";
   }
   else {
      $class = "SyTest::Homeserver::Synapse::Direct";
   }

   return $class->SUPER::new( %args );
}

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      ports synapse_dir extra_args python coverage dendron bind_host
   );

   defined $self->{ports}{$_} or croak "Need a '$_' port\n"
      for qw( synapse synapse_unsecure synapse_metrics );

   $self->{paths} = {};

   $self->SUPER::_init( $args );
}

sub configure
{
   my $self = shift;
   my %params = @_;

   exists $params{$_} and $self->{$_} = delete $params{$_} for qw(
      print_output filter_output
      config
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

sub start
{
   my $self = shift;

   my $port = $self->{ports}{synapse};
   my $output = $self->{output};

   my $hs_dir = $self->{hs_dir};

   my $db_config_path = "database.yaml";
   my $db_config_abs_path = "$hs_dir/${db_config_path}";
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

   $self->check_db_config( $db_type, $db_config, %db_args );

   if( defined $db_type ) {
      my $clear_meth = "clear_db_${db_type}";
      $self->$clear_meth( %db_args );
   }

   # Clean up the media_store directory each time, or else it fills up with
   # thousands of automatically-generated avatar images
   if( -d "$hs_dir/media_store" ) {
      remove_tree( "$hs_dir/media_store" );
   }

   if( -d "$hs_dir/uploads" ) {
      remove_tree( "$hs_dir/uploads" );
   }

   my $cwd = getcwd;
   my $log = "$hs_dir/homeserver.log";

   my $listeners = [ $self->generate_listeners ];
   my $bind_host = $self->{bind_host};
   my $server_name = "$bind_host:" . $self->secure_port;

   my $cert_file = $self->{paths}{cert_file} = "$hs_dir/cert.pem";
   my $key_file  = $self->{paths}{key_file}  = "$hs_dir/key.pem";
   my $log_config_file = "$hs_dir/log.config";

   my $macaroon_secret_key = "secret_$port";
   my $registration_shared_secret = "reg_secret";

   my $config_path = $self->{paths}{config} = $self->write_yaml_file( "config.yaml" => {
        server_name => $server_name,
        log_file => "$log",
        ( -f $log_config_file ) ? ( log_config => $log_config_file ) : (),
        tls_certificate_path => $cert_file,
        tls_private_key_path => $key_file,
        tls_dh_params_path => "$cwd/keys/tls.dh",
        use_insecure_ssl_client_just_for_testing_do_not_use => 1,
        rc_messages_per_second => 1000,
        rc_message_burst_count => 1000,
        enable_registration => "true",
        database => $db_config,
        database_config => $db_config_path,
        macaroon_secret_key => $macaroon_secret_key,
        registration_shared_secret => $registration_shared_secret,

        use_frozen_events => "true",

        allow_guest_access => "True",
        invite_3pid_guest => "true",

        # Metrics are always useful
        enable_metrics => 1,
        report_stats => "False",

        perspectives => { servers => {} },

        # Stack traces are useful
        full_twisted_stacktraces => "true",

        listeners => $listeners,

        bcrypt_rounds => 0,

        # If we're using dendron-style split workers, we need to disable these
        # things in the main process
        start_pushers      => ( not $self->{dendron} ),
        notify_appservices => ( not $self->{dendron} ),
        send_federation    => ( not $self->{dendron} ),

        url_preview_enabled => "true",
        url_preview_ip_range_blacklist => [],

        media_store_path => "$hs_dir/media_store",
        uploads_path => "$hs_dir/uploads_path",

        %{ $self->{config} },
   } );

   $self->{paths}{log} = $log;

   {
      # create or truncate
      open my $tmph, ">", $log or die "Cannot open $log for writing - $!";
      foreach my $suffix ( qw( appservice media_repository federation_reader synchrotron federation_sender ) ) {
         open my $tmph, ">", "$log.$suffix" or die "Cannot open $log.$suffix for writing - $!";
      }
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
      "--server-name" => "$bind_host:$port";

   $output->diag( "Generating config for port $port" );

   my @config_command = (
      @synapse_command, "--generate-config", "--report-stats=no"
   );

   my @command = $self->wrap_synapse_command( @synapse_command );

   my $env = {
      "PYTHONPATH" => $pythonpath,
      "PATH" => $ENV{PATH},
      "PYTHONDONTWRITEBYTECODE" => "Don't write .pyc files",
   };

   my $loop = $self->loop;

   my $started_future = $loop->new_future;

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

         $output->diag( "Connecting to server $port" );

         $self->adopt_future(
            $self->await_connectable( $bind_host, $self->_start_await_port )->then( sub {
               $output->diag( "Connected to server $port" );

               $started_future->done;
            })
         );

         $self->open_logfile;
      }
   );

   return $started_future;
}

sub check_db_config
{
   # Normally don't care
}

sub generate_listeners
{
   my $self = shift;

   my $bind_host = $self->{bind_host};

   my @listeners;

   if( my $unsecure_port = $self->{ports}{synapse_unsecure} ) {
      push @listeners, {
         type => "http",
         port => $unsecure_port,
         bind_address => $bind_host,
         tls => 0,
         resources => [{
            names => [ "client", "federation", "replication", "metrics" ], compress => 0
         }]
      }
   }

   return @listeners,
      {
         type => "metrics",
         port => $self->{ports}{synapse_metrics},
         bind_address => $bind_host,
         tls => 0,
      };
}

sub wrap_synapse_command
{
   my $self = shift;
   return @_;
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
      if( WIFEXITED($exitcode) ) {
         warn "Main homeserver process exited " . WEXITSTATUS($exitcode) . "\n";
      }
      else {
         warn "Main homeserver process failed - code=$exitcode\n";
      }

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
         filename => $self->{paths}{log},
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

sub rotate_logfile
{
   my $self = shift;
   my ( $newname ) = @_;

   my $logpath = $self->{paths}{log};

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

package SyTest::Homeserver::Synapse::Direct;
use base qw( SyTest::Homeserver::Synapse );

sub generate_listeners
{
   my $self = shift;

   return
      {
         type => "http",
         port => $self->{ports}{synapse},
         bind_address => $self->{bind_host},
         tls => 1,
         resources => [{
            names => [ "client", "federation", "replication", "metrics" ], compress => 0
         }]
      },
      $self->SUPER::generate_listeners;
}

sub _start_await_port
{
   my $self = shift;
   return $self->{ports}{synapse};
}

sub secure_port
{
   my $self = shift;
   return $self->{ports}{synapse};
}

sub unsecure_port
{
   my $self = shift;
   return $self->{ports}{synapse_unsecure};
}

package SyTest::Homeserver::Synapse::ViaDendron;
use base qw( SyTest::Homeserver::Synapse );

use Carp;

sub _init
{
   my $self = shift;
   $self->SUPER::_init( @_ );

   defined $self->{ports}{$_} or croak "Need a '$_' port\n"
      for qw( dendron );
}

sub check_db_config
{
   my $self = shift;
   my ( $type, $config, %args ) = @_;

   $type eq "pg" or die "Dendron can only run against postgres";

   return $self->SUPER::check_db_config( @_ );
}

sub wrap_synapse_command
{
   my $self = shift;

   my $bind_host = $self->{bind_host};
   my $log = $self->{paths}{log};

   -x $self->{dendron} or
      die "Cannot exec($self->{dendron}) - $!";

   my @command = (
      $self->{dendron},
      "--synapse-python" => $self->{python},
      "--synapse-config" => $self->{paths}{config},
      "--synapse-url" => "http://$bind_host:$self->{ports}{synapse_unsecure}",
      "--cert-file" => $self->{paths}{cert_file},
      "--key-file"  => $self->{paths}{key_file},
      "--addr" => "$bind_host:" . $self->{ports}{dendron},
   );

   {
      my $pusher_config_path = $self->write_yaml_file( "pusher.yaml" => {
         "worker_app"             => "synapse.app.pusher",
         "worker_log_file"        => "$log.pusher",
         "worker_replication_url" => "http://$bind_host:$self->{ports}{synapse_unsecure}/_synapse/replication",
         "worker_listeners"       => [
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               bind_address => $bind_host,
               port      => $self->{ports}{pusher_metrics},
            },
            {
               type => "manhole",
               port => $self->{ports}{pusher_manhole},
               bind_address => $bind_host,
            },
         ],
      } );

      push @command, "--pusher-config" => $pusher_config_path;
   }

   {
      my $appservice_config_path = $self->write_yaml_file( "appservice.yaml" => {
         "worker_app"             => "synapse.app.appservice",
         "worker_log_file"        => "$log.appservice",
         "worker_replication_url" => "http://$bind_host:$self->{ports}{synapse_unsecure}/_synapse/replication",
         "worker_listeners"       => [
            {
               type => "manhole",
               port => $self->{ports}{appservice_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{appservice_metrics},
               bind_address => $bind_host,
            },
         ],
      } );

      push @command, "--appservice-config" => $appservice_config_path;
   }

   {
      my $federation_sender_config_path = $self->write_yaml_file( "federation_sender.yaml" => {
         "worker_app"             => "synapse.app.federation_sender",
         "worker_log_file"        => "$log.federation_sender",
         "worker_replication_url" => "http://$bind_host:$self->{ports}{synapse_unsecure}/_synapse/replication",
         "worker_listeners"       => [
            {
               type => "manhole",
               port => $self->{ports}{federation_sender_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{federation_sender_metrics},
               bind_address => $bind_host,
            },
         ],
      } );

      push @command, "--federation-sender-config" => $federation_sender_config_path;
   }

   {
      my $synchrotron_config_path = $self->write_yaml_file( "synchrotron.yaml" => {
         "worker_app"             => "synapse.app.synchrotron",
         "worker_log_file"        => "$log.synchrotron",
         "worker_replication_url" => "http://$bind_host:$self->{ports}{synapse_unsecure}/_synapse/replication",
         "worker_listeners"       => [
            {
               type      => "http",
               resources => [{ names => ["client"] }],
               port      => $self->{ports}{synchrotron},
               bind_address => $bind_host,
            },
            {
               type => "manhole",
               port => $self->{ports}{synchrotron_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{synchrotron_metrics},
               bind_address => $bind_host,
            },
         ],
      } );

      push @command,
         "--synchrotron-config" => $synchrotron_config_path,
         "--synchrotron-url" => "http://$bind_host:$self->{ports}{synchrotron}";
   }

   {
      my $federation_reader_config_path = $self->write_yaml_file( "federation_reader.yaml" => {
         "worker_app"             => "synapse.app.federation_reader",
         "worker_log_file"        => "$log.federation_reader",
         "worker_replication_url" => "http://$bind_host:$self->{ports}{synapse_unsecure}/_synapse/replication",
         "worker_listeners"       => [
            {
               type      => "http",
               resources => [{ names => ["federation"] }],
               port      => $self->{ports}{federation_reader},
               bind_address => $bind_host,
            },
            {
               type => "manhole",
               port => $self->{ports}{federation_reader_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{federation_reader_metrics},
               bind_address => $bind_host,
            },
         ],
      } );

      push @command,
         "--federation-reader-config" => $federation_reader_config_path,
         "--federation-reader-url" => "http://$bind_host:$self->{ports}{federation_reader}";
   }

   {
      my $media_repository_config_path = $self->write_yaml_file( "media_repository.yaml" => {
         "worker_app"             => "synapse.app.media_repository",
         "worker_log_file"        => "$log.media_repository",
         "worker_replication_url" => "http://$bind_host:$self->{ports}{synapse_unsecure}/_synapse/replication",
         "worker_listeners"       => [
            {
               type      => "http",
               resources => [{ names => ["media"] }],
               port      => $self->{ports}{media_repository},
               bind_address => $bind_host,
            },
            {
               type => "manhole",
               port => $self->{ports}{media_repository_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{media_repository_metrics},
               bind_address => $bind_host,
            },
         ],
      } );

      push @command,
         "--media-repository-config" => $media_repository_config_path,
         "--media-repository-url" => "http://$bind_host:$self->{ports}{media_repository}";
   }

   {
      my $client_reader_config_path = $self->write_yaml_file( "client_reader.yaml" => {
         "worker_app"             => "synapse.app.client_reader",
         "worker_log_file"        => "$log.client_reader",
         "worker_replication_url" => "http://$bind_host:$self->{ports}{synapse_unsecure}/_synapse/replication",
         "worker_listeners"       => [
            {
               type      => "http",
               resources => [{ names => ["client"] }],
               port      => $self->{ports}{client_reader},
               bind_address => $bind_host,
            },
            {
               type => "manhole",
               port => $self->{ports}{client_reader_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{client_reader_metrics},
               bind_address => $bind_host,
            },
         ],
      } );

      push @command,
         "--client-reader-config" => $client_reader_config_path,
         "--client-reader-url" => "http://$bind_host:$self->{ports}{client_reader}";
   }

   return @command;
}

sub _start_await_port
{
   my $self = shift;
   return $self->{ports}{dendron};
}

sub secure_port
{
   my $self = shift;
   return $self->{ports}{dendron};
}

sub unsecure_port
{
   my $self = shift;
   die "dendron does not have an unsecure port mode\n";
}

package SyTest::Homeserver::Synapse::ViaHaproxy;
# For now we'll base this on "ViaDendron" so that dendron manages the multiple
# workers. Longer-term we'll want to have a specific worker management system
# so we can avoid dendron itself.
use base qw( SyTest::Homeserver::Synapse::ViaDendron );

use Carp;

use File::Slurper qw( read_binary );

use constant HAPROXY_BIN => "/usr/sbin/haproxy";

sub _init
{
   my $self = shift;
   $self->SUPER::_init( @_ );

   defined $self->{ports}{$_} or croak "Need a '$_' port\n"
      for qw( haproxy );
}

sub start
{
   my $self = shift;

   my $output = $self->{output};

   return $self->SUPER::start->then( sub {
      # We know synapse has started, so lets steal its SSL keys
      # haproxy wants a "combined" pemfile, which is just the cert and key concatenated together

      my $cert = read_binary( $self->{paths}{cert_file} );
      my $key  = read_binary( $self->{paths}{key_file} );

      $self->{paths}{pem_file} = $self->write_file( "combined.pem", $cert . $key );

      $self->{haproxy_config} = $self->write_file( "haproxy.conf", $self->generate_haproxy_config );

      $output->diag( "Starting haproxy on port $self->{ports}{haproxy}" );

      $self->add_child( $self->{haproxy_proc} = IO::Async::Process->new(
         command => [ HAPROXY_BIN, "-db", "-f", $self->{haproxy_config} ],
         on_finish => sub {
            my ( undef, $exitcode ) = @_;
            print STDERR "\n\nhaproxy died $exitcode\n\n";
         },
      ) );

      return $self->await_connectable( $self->{bind_host}, $self->{ports}{haproxy} )
         ->on_done( sub { $output->diag( "haproxy started" ) } );
   });
}

sub kill
{
   my $self = shift;
   my ( $signal ) = @_;

   $self->SUPER::kill( @_ );

   if( $self->{haproxy_proc} and my $pid = $self->{haproxy_proc}->pid ) {
      kill $signal => $pid;
   }
}

sub generate_haproxy_config
{
   my $self = shift;

   my $bind_host = $self->{bind_host};
   my $ports = $self->{ports};

   return <<"EOCONFIG";
global
    tune.ssl.default-dh-param 2048

    ssl-default-bind-ciphers "EECDH+ECDSA+AESGCM EECDH+aRSA+AESGCM EECDH+ECDSA+SHA384 EECDH+ECDSA+SHA256 EECDH+aRSA+SHA384 EECDH+aRSA+SHA256 EECDH+aRSA+RC4 EECDH EDH+aRSA RC4 !aNULL !eNULL !LOW !3DES !MD5 !EXP !PSK !SRP !DSS !RC4"
    ssl-default-bind-options no-sslv3

defaults
    mode http

    timeout connect 5s
    timeout client 90s
    timeout server 90s

    compression algo gzip
    compression type text/plain text/html text/xml application/json text/css

    option forwardfor

frontend http-in
    bind ${bind_host}:$ports->{haproxy} ssl crt $self->{paths}{pem_file}

    default_backend synapse

    acl path_syncrotron path_beg /_matrix/client/v2_alpha/sync
    acl path_syncrotron path_beg /_matrix/client/r0/sync
    acl path_syncrotron path_beg /_matrix/client/r0/events
    acl path_syncrotron path_beg /_matrix/client/api/v1/events
    acl path_syncrotron path_beg /_matrix/client/api/v1/initialSync
    acl path_syncrotron path_beg /_matrix/client/r0/initialSync
    acl path_syncrotron path_reg ^/_matrix/client/api/v1/rooms/[^/]+/initialSync\$
    acl path_syncrotron path_reg ^/_matrix/client/r0/rooms/[^/]+/initialSync\$
    use_backend synchrotrons if path_syncrotron

    acl path_federation_reader path_beg /_matrix/federation/v1/event/
    acl path_federation_reader path_beg /_matrix/federation/v1/state/
    acl path_federation_reader path_beg /_matrix/federation/v1/state_ids/
    acl path_federation_reader path_beg /_matrix/federation/v1/backfill/
    acl path_federation_reader path_beg /_matrix/federation/v1/get_missing_events/
    acl path_federation_reader path_beg /_matrix/federation/v1/publicRooms
    use_backend federation_reader if path_federation_reader

    acl path_media_repository path_beg /_matrix/media/
    use_backend media_repository if path_media_repository

    acl path_client_reader path_beg /_matrix/client/r0/publicRooms
    acl path_client_reader path_beg /_matrix/client/api/v1/publicRooms
    use_backend client_reader if path_client_reader

backend synapse
    server synapse ${bind_host}:$ports->{synapse_unsecure}

backend synchrotrons
    server synchrotron ${bind_host}:$ports->{synchrotron}

backend federation_reader
    server federation_reader ${bind_host}:$ports->{federation_reader}

backend media_repository
    server media_repository ${bind_host}:$ports->{media_repository}

backend client_reader
    server client_reader ${bind_host}:$ports->{client_reader}

EOCONFIG
}

sub secure_port
{
   my $self = shift;
   return $self->{ports}{haproxy};
}

sub unsecure_port
{
   my $self = shift;
   die "haproxy does not have an unsecure port mode\n";
}

1;
