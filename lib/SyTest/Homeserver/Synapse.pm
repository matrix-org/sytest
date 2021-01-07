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

use JSON;

use SyTest::SSL qw( ensure_ssl_key create_ssl_cert );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      synapse_dir extra_args python coverage
   );

   $self->{paths} = {};
   $self->{workers} = 0;
   $self->{redis_host} = '';

   $self->SUPER::_init( $args );

   my $idx = $self->{hs_index};
   $self->{ports} = {
      synapse                  => main::alloc_port( "synapse[$idx]" ),
      synapse_unsecure         => main::alloc_port( "synapse[$idx].unsecure" ),
      synapse_metrics          => main::alloc_port( "synapse[$idx].metrics" ),
      synapse_replication_tcp  => main::alloc_port( "synapse[$idx].replication_tcp" ),

      pusher_metrics => main::alloc_port( "pusher[$idx].metrics" ),
      pusher_manhole => main::alloc_port( "pusher[$idx].manhole" ),

      synchrotron         => main::alloc_port( "synchrotron[$idx]" ),
      synchrotron_metrics => main::alloc_port( "synchrotron[$idx].metrics" ),
      synchrotron_manhole => main::alloc_port( "synchrotron[$idx].manhole" ),

      federation_reader         => main::alloc_port( "federation_reader[$idx]" ),
      federation_reader_metrics => main::alloc_port( "federation_reader[$idx].metrics" ),
      federation_reader_manhole => main::alloc_port( "federation_reader[$idx].manhole" ),

      media_repository => main::alloc_port( "media_repository[$idx]" ),
      media_repository_metrics => main::alloc_port( "media_repository[$idx].metrics" ),
      media_repository_manhole => main::alloc_port( "media_repository[$idx].manhole" ),

      appservice_metrics => main::alloc_port( "appservice[$idx].metrics" ),
      appservice_manhole => main::alloc_port( "appservice[$idx].manhole" ),

      federation_sender_metrics => main::alloc_port( "federation_sender1[$idx].metrics" ),
      federation_sender_manhole => main::alloc_port( "federation_sender[$idx].manhole" ),

      client_reader         => main::alloc_port( "client_reader[$idx]" ),
      client_reader_metrics => main::alloc_port( "client_reader[$idx].metrics" ),
      client_reader_manhole => main::alloc_port( "client_reader[$idx].manhole" ),

      user_dir         => main::alloc_port( "user_dir[$idx]" ),
      user_dir_metrics => main::alloc_port( "user_dir[$idx].metrics" ),
      user_dir_manhole => main::alloc_port( "user_dir[$idx].manhole" ),

      event_creator         => main::alloc_port( "event_creator[$idx]" ),
      event_creator_metrics => main::alloc_port( "event_creator[$idx].metrics" ),
      event_creator_manhole => main::alloc_port( "event_creator[$idx].manhole" ),

      frontend_proxy         => main::alloc_port( "frontend_proxy[$idx]" ),
      frontend_proxy_metrics => main::alloc_port( "frontend_proxy[$idx].metrics" ),
      frontend_proxy_manhole => main::alloc_port( "frontend_proxy[$idx].manhole" ),

      event_persister1         => main::alloc_port( "event_persister1[$idx]" ),
      event_persister1_metrics => main::alloc_port( "event_persister1[$idx].metrics" ),
      event_persister1_manhole => main::alloc_port( "event_persister1[$idx].manhole" ),

      event_persister2         => main::alloc_port( "event_persister2[$idx]" ),
      event_persister2_metrics => main::alloc_port( "event_persister2[$idx].metrics" ),
      event_persister2_manhole => main::alloc_port( "event_persister2[$idx].manhole" ),

      haproxy => main::alloc_port( "haproxy[$idx]" ),
   };
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

sub start
{
   my $self = shift;

   my $hs_index = $self->{hs_index};
   my $port = $self->{ports}{synapse};
   my $output = $self->{output};

   my $hs_dir = $self->{hs_dir};

   my %db_configs = $self->_get_dbconfigs(
      type => 'sqlite',
      args => {
         database => ":memory:", #"$hs_dir/homeserver.db",
      },
   );

   # convert sytest db args onto synapse db args
   for my $db ( keys %db_configs ) {
      my %db_config = %{ $db_configs{$db} };

      my $db_type = $db_config{type};

      if( $db_type eq "pg" ) {
         $db_configs{$db}{name} = 'psycopg2';
      }
      else {
         # must be sqlite
         $db_configs{$db}{name} = 'sqlite3';
      }
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
   my $unsecure_port = $self->{ports}{synapse_unsecure};

   my $macaroon_secret_key = "secret_$port";
   my $registration_shared_secret = "reg_secret";

   $self->{paths}{cert_file} = "$hs_dir/tls.crt";
   $self->{paths}{key_file} = "$hs_dir/tls.key";

   ensure_ssl_key( $self->{paths}{key_file} );
   create_ssl_cert( $self->{paths}{cert_file}, $self->{paths}{key_file}, $bind_host );

   # make it possible to use a custom log config file
   my $log_config_file = "$hs_dir/log.config";
   if( ! -f $log_config_file ) {
      $log_config_file = $self->configure_logger("homeserver");
   }

   my $config_path = $self->{paths}{config} = $self->write_yaml_file( "config.yaml" => {
        server_name => $self->server_name,
        log_config => $log_config_file,
        public_baseurl => "http://${bind_host}:$unsecure_port",

        # We configure synapse to use a TLS cert which is signed by our dummy CA...
        tls_certificate_path => $self->{paths}{cert_file},
        tls_private_key_path => $self->{paths}{key_file},

        # ... and configure it to trust that CA for federation connections...
        federation_custom_ca_list => [
           "$cwd/keys/ca.crt",
        ],

        # ... but synapse currently lacks such an option for non-federation
        # connections. Instead we just turn of cert checking for them like
        # this:
        use_insecure_ssl_client_just_for_testing_do_not_use => 1,

        rc_messages_per_second => 1000,
        rc_message_burst_count => 1000,
        rc_registration => {
            per_second => 1000,
            burst_count => 1000,
        },
        rc_login => {
            address => {
                per_second => 1000,
                burst_count => 1000,
            },
            account => {
                per_second => 1000,
                burst_count => 1000,
            },
            failed_attempts => {
                per_second => 1000,
                burst_count => 1000,
            }
        },

        rc_federation => {
           # allow 100 requests per sec instead of 10
           sleep_limit => 100,
           window_size => 1000,
        },

        rc_joins => {
           local => {
             per_second => 1000,
              burst_count => 1000,
           },
           remote => {
             per_second => 1000,
              burst_count => 1000,
           },
        },

        enable_registration => "true",
        databases => \%db_configs,
        macaroon_secret_key => $macaroon_secret_key,
        registration_shared_secret => $registration_shared_secret,

        pid_file => "$hs_dir/homeserver.pid",

        use_frozen_dicts => "true",

        allow_guest_access => "True",

        # Metrics are always useful
        enable_metrics => 1,
        report_stats => "False",

        perspectives => { servers => {} },

        listeners => $listeners,

        # we reduce the number of bcrypt rounds to make generating users
        # faster, but note that python's bcrypt complains if rounds < 4,
        # so this is effectively the minimum.
        bcrypt_rounds => 4,

        # We remove the ip range blacklist which by default blocks federation
        # connections to local homeservers, of which sytest uses extensively
        ip_range_blacklist => [],
        federation_ip_range_blacklist => [],

        # If we're using workers we need to disable these things in the main
        # process
        start_pushers         => ( not $self->{workers} ),
        notify_appservices    => ( not $self->{workers} ),
        send_federation       => ( not $self->{workers} ),
        update_user_directory => ( not $self->{workers} ),
        enable_media_repo     => ( not $self->{workers} ),
        run_background_tasks_on  => ( $self->{workers} ? "background_worker1" : "master" ),

        url_preview_enabled => "true",
        url_preview_ip_range_blacklist => [],

        media_store_path => "$hs_dir/media_store",
        uploads_path => "$hs_dir/uploads_path",

        # Both of these settings default to false in order to preserve privacy.
        # Sytest assumes that the room directory is open to ensure that the
        # open behaviour can be tested, and the default case is handled through
        # unit tests.
        allow_public_rooms_over_federation => "true",
        allow_public_rooms_without_auth => "true",

        user_agent_suffix => "homeserver[". $self->{hs_index} . "]",

        require_membership_for_aliases => "false",

        # Enable ephemeral message support (MSC2228)
        enable_ephemeral_messages => "true",

        $self->{recaptcha_config} ? (
           recaptcha_siteverify_api => $self->{recaptcha_config}->{siteverify_api},
           recaptcha_public_key     => $self->{recaptcha_config}->{public_key},
           recaptcha_private_key    => $self->{recaptcha_config}->{private_key},
        ) : (),

        $self->{smtp_server_config} ? (
           email => {
              smtp_host => $self->{smtp_server_config}->{host},
              smtp_port => $self->{smtp_server_config}->{port},
              notif_from => 'synapse@localhost',
           },
        ) : (),

        instance_map => {
           "event_persister1" => {
              host => "$bind_host",
              port => $self->{ports}{event_persister1},
           },
           "event_persister2" => {
              host => "$bind_host",
              port => $self->{ports}{event_persister2},
           },
           "client_reader" => {
              host => "$bind_host",
              port => $self->{ports}{client_reader},
           },
        },

        stream_writers => {
           events => $self->{redis_host} ne '' ? [ "event_persister1", "event_persister2" ] : "master",

           # There's no particular reason to choose client_reader, but I
           # couldn't think of a better place and I'm not sure we want to add
           # more workers at this point
           to_device => $self->{redis_host} ne '' ? [ "client_reader" ] : "master",
        },

        # We use a high limit so the limit is never reached, but enabling the
        # limit ensures that the code paths get hit. This helps testing the
        # feature with worker mode.
        limit_usage_by_mau => "true",
        max_mau_value => 50000000,

        redis => {
           enabled => $self->{redis_host} ne '',
           host    => $self->{redis_host},
        },

        map {
           defined $self->{$_} ? ( $_ => $self->{$_} ) : ()
        } qw(
           replication_torture_level
           cas_config
           app_service_config_files
        ),
   } );

   $self->{paths}{log} = $log;

   {
      # create or truncate
      open my $tmph, ">", $log or die "Cannot open $log for writing - $!";
      foreach my $suffix ( qw( appservice media_repository federation_reader synchrotron federation_sender client_reader user_dir event_creator frontend_proxy background_worker ) ) {
         open my $tmph, ">", "$log.$suffix" or die "Cannot open $log.$suffix for writing - $!";
      }
   }

   my @synapse_command = $self->_generate_base_synapse_command();

   $output->diag( "Generating config for port $port" );

   my @config_command = (
      @synapse_command, "--generate-config", "--report-stats=no",
      "--server-name", $self->server_name
   );

   my $env = {
      "PATH" => $ENV{PATH},
      "PYTHONDONTWRITEBYTECODE" => "Don't write .pyc files",
      "SYNAPSE_TEST_PATCH_LOG_CONTEXTS" => 1,
   };

   my $loop = $self->loop;

   $output->diag(
      "Creating config for server $hs_index with command "
         . join( " ", @config_command ),
   );

   return $self->_run_command(
      setup => [ env => $env ],
      command => [ @config_command ],
   )->then( sub {
      $output->diag(
        "Starting server $hs_index for port $port"
      );

      $self->_start_synapse( env => $env )
   })->on_done( sub {
      $output->diag("Started synapse $hs_index");
      $self->open_logfile();
   });
}

sub _generate_base_synapse_command
{
   my $self = shift;
   my %params = @_;

   my $app = $params{app} // "synapse.app.homeserver";

   my @synapse_command = ( $self->{python} );

   if( $self->{coverage} ) {
      # Ensures that even --generate-config has coverage reports. This is intentional
      push @synapse_command,
         "-m", "coverage", "run", "--source=$self->{synapse_dir}/synapse", "--rcfile=$self->{synapse_dir}/.coveragerc";
   }

   push @synapse_command,
      "-m", $app,
      "--config-path" => $self->{paths}{config};


   my @command = (
      @synapse_command,
      @{ $self->{extra_args} },
   );

   return @command
}

sub _start_synapse
{
   my $self = shift;
   my %params = @_;

   my $env = $params{env};

   my $bind_host = $self->{bind_host};
   my @synapse_command = $self->_generate_base_synapse_command();

   $self->_start_process_and_await_notify(
      setup => [ env => $env ],
      command => \@synapse_command,
   );
}

sub generate_listeners
{
   my $self = shift;

   my $bind_host = $self->{bind_host};

   my @listeners;

   if( my $unsecure_port = $self->{ports}{synapse_unsecure} ) {
      push @listeners, {
         type         => "http",
         port         => $unsecure_port,
         bind_address => $bind_host,
         resources    => [{
            names => [ "client", "federation", "replication", "metrics" ]
         }]
      }
   }

   if( my $replication_tcp_port = $self->{ports}{synapse_replication_tcp} ) {
      push @listeners, {
         type         => "replication",
         port         => $replication_tcp_port,
         bind_address => $bind_host,
      }
   }

   return @listeners,
      {
         type         => "metrics",
         port         => $self->{ports}{synapse_metrics},
         bind_address => $bind_host,
      };
}

sub wrap_synapse_command
{
   my $self = shift;
   return @_;
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
   my $port = $self->{ports}{synapse};

   while( $$bufref =~ s/^(.*)\n// ) {
      my $line = $1;

      push @{ $self->{stderr_lines} }, $line;
      shift @{ $self->{stderr_lines} } while @{ $self->{stderr_lines} } > 20;

      if( $self->{print_output} ) {
         my $filter = $self->{filter_output};
         if( !$filter or $line =~ m/$filter/ ) {
            print STDERR "\e[1;35m[server $port]\e[m: $line\n";
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
      my $port = $self->{ports}{synapse};
      print STDERR "\e[1;35m[server $port]\e[m: $_\n"
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


sub server_name
{
   my $self = shift;
   return $self->{bind_host} . ":" . $self->secure_port;
}

sub http_api_host
{
   my $self = shift;
   return $self->{bind_host};
}

sub federation_port
{
   my $self = shift;
   return $self->secure_port;
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
         tls => JSON::true,
         resources => [{
            names => [ "client", "federation", "replication", "metrics" ]
         }]
      },
      $self->SUPER::generate_listeners;
}

package SyTest::Homeserver::Synapse::ViaHaproxy;
use base qw( SyTest::Homeserver::Synapse );

use Carp;
use File::Slurper qw( read_binary );

use constant HAPROXY_BIN => $ENV{HAPROXY_BIN} // "/usr/sbin/haproxy";

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->SUPER::_init( @_ );

   $self->{workers} = delete $args->{workers};
   $self->{redis_host} = delete $args->{redis_host};

   if( my $level = delete $args->{torture_replication} ) {
      # torture the replication protocol a bit, to replicate bugs.
      # (value is the number of ms to wait before sending out each batch of
      # updates.)
      $self->{replication_torture_level} = $level;
   }

   defined $self->{ports}{$_} or croak "Need a '$_' port\n"
      for qw( haproxy );
}

sub _check_db_config
{
   my $self = shift;
   my ( %config ) = @_;

   $config{type} eq "pg" or die "Dendron can only run against postgres";

   return $self->SUPER::_check_db_config( @_ );
}

sub _start_synapse
{
   my $self = shift;
   my %params = @_;

   my $env = $params{env};

   my $bind_host = $self->{bind_host};
   my $log = $self->{paths}{log};
   my $hsdir = $self->{hs_dir};

   my @worker_configs = ();

   {
      my $pusher_config = {
         "worker_app"              => "synapse.app.pusher",
         "worker_name"             => "pusher",
         "worker_pid_file"         => "$hsdir/pusher.pid",
         "worker_log_config"       => $self->configure_logger("pusher"),
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_listeners"        => [
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
      };

      push @worker_configs, $pusher_config;
   }

   {
      my $appservice_config = {
         "worker_app"              => "synapse.app.appservice",
         "worker_name"             => "appservice",
         "worker_pid_file"         => "$hsdir/appservice.pid",
         "worker_log_config"       => $self->configure_logger("appservice"),
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_listeners"        => [
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
      };

      push @worker_configs, $appservice_config;
   }

   {
      my $federation_sender_config = {
         "worker_app"              => "synapse.app.federation_sender",
         "worker_name"             => "federation_sender",
         "worker_pid_file"         => "$hsdir/federation_sender.pid",
         "worker_log_config"       => $self->configure_logger("federation_sender"),
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_listeners"        => [
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
      };

      push @worker_configs, $federation_sender_config;
   }

   {
      my $synchrotron_config = {
         "worker_app"              => "synapse.app.synchrotron",
         "worker_name"             => "synchrotron",
         "worker_pid_file"         => "$hsdir/synchrotron.pid",
         "worker_log_config"       => $self->configure_logger("synchrotron"),
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_listeners"        => [
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
      };

      push @worker_configs, $synchrotron_config;
   }

   {
      my $federation_reader_config = {
         "worker_app"              => "synapse.app.federation_reader",
         "worker_name"             => "federation_reader",
         "worker_pid_file"         => "$hsdir/federation_reader.pid",
         "worker_log_config"       => $self->configure_logger("federation_reader"),
         "worker_replication_host" => "$bind_host",
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
         "worker_listeners"        => [
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
      };

      push @worker_configs, $federation_reader_config;
   }

   {
      my $media_repository_config ={
         "worker_app"              => "synapse.app.media_repository",
         "worker_name"             => "media_repository",
         "worker_pid_file"         => "$hsdir/media_repository.pid",
         "worker_log_config"       => $self->configure_logger("media_repository"),
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_listeners"        => [
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
      };

      push @worker_configs, $media_repository_config;
   }

   {
      my $client_reader_config = {
         "worker_app"                   => "synapse.app.client_reader",
         "worker_name"                  => "client_reader",
         "worker_pid_file"              => "$hsdir/client_reader.pid",
         "worker_log_config"            => $self->configure_logger("client_reader"),
         "worker_replication_host"      => "$bind_host",
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_replication_port"      => $self->{ports}{synapse_replication_tcp},
         "worker_listeners"             => [
            {
               type      => "http",
               resources => [{ names => ["client", "replication"] }],
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
      };

      push @worker_configs, $client_reader_config;
   }

   {
      my $user_dir_config = {
         "worker_app"              => "synapse.app.user_dir",
         "worker_name"             => "user_dir",
         "worker_pid_file"         => "$hsdir/user_dir.pid",
         "worker_log_config"       => $self->configure_logger("user_dir"),
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_listeners"        => [
            {
               type      => "http",
               resources => [{ names => ["client"] }],
               port      => $self->{ports}{user_dir},
               bind_address => $bind_host,
            },
            {
               type => "manhole",
               port => $self->{ports}{user_dir_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{user_dir_metrics},
               bind_address => $bind_host,
            },
         ],
      };

      push @worker_configs, $user_dir_config;
   }

   {
      my $event_creator_config = {
         "worker_app"                   => "synapse.app.event_creator",
         "worker_name"                  => "event_creator",
         "worker_pid_file"              => "$hsdir/event_creator.pid",
         "worker_log_config"            => $self->configure_logger("event_creator"),
         "worker_replication_host"      => "$bind_host",
         "worker_replication_port"      => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_listeners"             => [
            {
               type      => "http",
               resources => [{ names => ["client"] }],
               port      => $self->{ports}{event_creator},
               bind_address => $bind_host,
            },
            {
               type => "manhole",
               port => $self->{ports}{event_creator_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{event_creator_metrics},
               bind_address => $bind_host,
            },
         ],
      };

      push @worker_configs, $event_creator_config;
   }

   {
      my $frontend_proxy_config = {
         "worker_app"                   => "synapse.app.frontend_proxy",
         "worker_name"                  => "frontend_proxy1",
         "worker_pid_file"              => "$hsdir/frontend_proxy.pid",
         "worker_log_config"            => $self->configure_logger("frontend_proxy"),
         "worker_replication_host"      => "$bind_host",
         "worker_replication_port"      => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_main_http_uri"         => "http://$bind_host:$self->{ports}{synapse_unsecure}",
         "worker_listeners"             => [
            {
               type      => "http",
               resources => [{ names => ["client", "replication"] }],
               port      => $self->{ports}{frontend_proxy},
               bind_address => $bind_host,
            },
            {
               type => "manhole",
               port => $self->{ports}{frontend_proxy_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{frontend_proxy_metrics},
               bind_address => $bind_host,
            },
         ],
      };

      push @worker_configs, $frontend_proxy_config;
   }

   {
      my $background_worker_config = {
         "worker_app"                   => "synapse.app.generic_worker",
         "worker_name"                  => "background_worker1",
         "worker_pid_file"              => "$hsdir/background_worker.pid",
         "worker_log_config"            => $self->configure_logger("background_worker"),
         "worker_replication_host"      => "$bind_host",
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_replication_port"      => $self->{ports}{synapse_replication_tcp},
         "worker_main_http_uri"         => "http://$bind_host:$self->{ports}{synapse_unsecure}",
      };

      push @worker_configs, $background_worker_config;
   }

   {
      my $event_persister1_config = {
         "worker_app"                   => "synapse.app.generic_worker",
         "worker_name"                  => "event_persister1",
         "worker_pid_file"              => "$hsdir/event_persister1.pid",
         "worker_log_config"            => $self->configure_logger("event_persister1"),
         "worker_replication_host"      => "$bind_host",
         "worker_replication_port"      => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_main_http_uri"         => "http://$bind_host:$self->{ports}{synapse_unsecure}",
         "worker_listeners"             => [
            {
               type      => "http",
               resources => [{ names => ["client", "replication"] }],
               port      => $self->{ports}{event_persister1},
               bind_address => $bind_host,
            },
            {
               type => "manhole",
               port => $self->{ports}{event_persister1_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{event_persister1_metrics},
               bind_address => $bind_host,
            },
         ],
      };

      push @worker_configs, $event_persister1_config;
   }

   {
      my $event_persister2_config = {
         "worker_app"                   => "synapse.app.generic_worker",
         "worker_name"                  => "event_persister2",
         "worker_pid_file"              => "$hsdir/event_persister2.pid",
         "worker_log_config"            => $self->configure_logger("event_persister2"),
         "worker_replication_host"      => "$bind_host",
         "worker_replication_port"      => $self->{ports}{synapse_replication_tcp},
         "worker_replication_http_port" => $self->{ports}{synapse_unsecure},
         "worker_main_http_uri"         => "http://$bind_host:$self->{ports}{synapse_unsecure}",
         "worker_listeners"             => [
            {
               type      => "http",
               resources => [{ names => ["client", "replication"] }],
               port      => $self->{ports}{event_persister2},
               bind_address => $bind_host,
            },
            {
               type => "manhole",
               port => $self->{ports}{event_persister2_manhole},
               bind_address => $bind_host,
            },
            {
               type      => "http",
               resources => [{ names => ["metrics"] }],
               port      => $self->{ports}{event_persister2_metrics},
               bind_address => $bind_host,
            },
         ],
      };

      push @worker_configs, $event_persister2_config;
   }

   my @base_synapse_command = $self->_generate_base_synapse_command();
   my $idx = $self->{hs_index};

   $self->_start_process_and_await_notify(
      setup => [ env => $env ],
      command => \@base_synapse_command,
      name => "synapse-$idx-master",
   )->then( sub {
      Future->needs_all(
         map {
            my $worker_app = $_->{worker_app};
            my $worker_name = $_->{worker_name};

            my $config_file = $self->write_yaml_file( $worker_name . ".yaml" => $_ );

            my @command = $self->_generate_base_synapse_command( app => $worker_app );
            push @command, "--config-path" => $config_file;

            $self->{output}->diag("Starting synapse $idx worker $worker_name");

            $self->_start_process_and_await_notify(
               setup => [ env => $env ],
               command => \@command,
               name => "synapse-$idx-$worker_name",
            )->then( sub {
               $self->{output}->diag("Started synapse $idx worker $worker_name");

               Future->done
            })
         } @worker_configs
      )
   })
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
      $self->{paths}{path_map_file} = $self->write_file( "path_map_file", $self->generate_haproxy_map );
      $self->{paths}{get_path_map_file} = $self->write_file( "get_path_map_file", $self->generate_haproxy_get_map );

      $self->{haproxy_config} = $self->write_file( "haproxy.conf", $self->generate_haproxy_config );

      $output->diag( "Starting haproxy on port $self->{ports}{haproxy}" );

      $self->_start_process_and_await_connectable(
         command => [ HAPROXY_BIN, "-db", "-f", $self->{haproxy_config} ],
         connect_host => $self->{bind_host},
         connect_port => $self->{ports}{haproxy},
      )->on_done( sub { $output->diag( "haproxy started" ) } );
   });
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

    acl has_get_map path -m reg -M -f $self->{paths}{get_path_map_file}
    use_backend %[path,map_reg($self->{paths}{get_path_map_file},synapse)] if has_get_map METH_GET

    use_backend %[path,map_reg($self->{paths}{path_map_file},synapse)]

backend synapse
    server synapse ${bind_host}:$ports->{synapse_unsecure}

backend synchrotron
    server synchrotron ${bind_host}:$ports->{synchrotron}

backend federation_reader
    server federation_reader ${bind_host}:$ports->{federation_reader}

backend media_repository
    server media_repository ${bind_host}:$ports->{media_repository}

backend client_reader
    server client_reader ${bind_host}:$ports->{client_reader}

backend user_dir
    server user_dir ${bind_host}:$ports->{user_dir}

backend event_creator
    server event_creator ${bind_host}:$ports->{event_creator}

backend frontend_proxy
    server frontend_proxy ${bind_host}:$ports->{frontend_proxy}

EOCONFIG
}

sub generate_haproxy_map
{
   my $self = shift;

   # The base haproxy routes. Note that we add more routes below if using
   # haproxy. Also, the routing for GET requests below takes precedence over
   # these routes.
   my $haproxy_map = <<'EOCONFIG';
^/_matrix/client/(v2_alpha|r0)/sync$                  synchrotron
^/_matrix/client/(api/v1|v2_alpha|r0)/events$         synchrotron
^/_matrix/client/(api/v1|r0)/initialSync$             synchrotron
^/_matrix/client/(api/v1|r0)/rooms/[^/]+/initialSync$ synchrotron

^/_matrix/media/    media_repository

^/_matrix/federation/v1/event/                        federation_reader
^/_matrix/federation/v1/state/                        federation_reader
^/_matrix/federation/v1/state_ids/                    federation_reader
^/_matrix/federation/v1/backfill/                     federation_reader
^/_matrix/federation/v1/get_missing_events/           federation_reader
^/_matrix/federation/v1/publicRooms                   federation_reader
^/_matrix/federation/v1/query/                        federation_reader
^/_matrix/federation/v1/make_join/                    federation_reader
^/_matrix/federation/v1/make_leave/                   federation_reader
^/_matrix/federation/v1/send_join/                    federation_reader
^/_matrix/federation/v1/send_leave/                   federation_reader
^/_matrix/federation/v1/invite/                       federation_reader
^/_matrix/federation/v1/query_auth/                   federation_reader
^/_matrix/federation/v1/event_auth/                   federation_reader
^/_matrix/federation/v1/exchange_third_party_invite/  federation_reader
^/_matrix/federation/v1/send/                         federation_reader
^/_matrix/federation/v1/get_groups_publicised         federation_reader
^/_matrix/federation/v1/user/devices/                 federation_reader
^/_matrix/key/v2/query                                federation_reader

^/_matrix/client/(api/v1|r0|unstable)/publicRooms$                client_reader
^/_matrix/client/(api/v1|r0|unstable)/rooms/.*/joined_members$    client_reader
^/_matrix/client/(api/v1|r0|unstable)/rooms/.*/context/.*$        client_reader
^/_matrix/client/(api/v1|r0|unstable)/rooms/.*/members$           client_reader
^/_matrix/client/(api/v1|r0|unstable)/rooms/.*/state$             client_reader
^/_matrix/client/(api/v1|r0|unstable)/login$                      client_reader
^/_matrix/client/(api/v1|r0|unstable)/account/3pid$               client_reader
^/_matrix/client/(api/v1|r0|unstable)/keys/query$                 client_reader
^/_matrix/client/(api/v1|r0|unstable)/keys/changes$               client_reader
^/_matrix/client/versions$                                        client_reader
^/_matrix/client/(api/v1|r0|unstable)/voip/turnServer$            client_reader
^/_matrix/client/(r0|unstable)/register$                          client_reader
^/_matrix/client/(r0|unstable)/auth/.*/fallback/web$              client_reader
^/_matrix/client/(api/v1|r0|unstable)/rooms/.*/messages$          client_reader
^/_matrix/client/(api/v1|r0|unstable)/get_groups_publicised$      client_reader
^/_matrix/client/(api/v1|r0|unstable)/joined_groups$              client_reader
^/_matrix/client/(api/v1|r0|unstable)/publicised_groups$          client_reader
^/_matrix/client/(api/v1|r0|unstable)/publicised_groups/          client_reader

^/_matrix/client/(api/v1|r0|unstable)/keys/upload  frontend_proxy

^/_matrix/client/(r0|unstable|v2_alpha)/user_directory/    user_dir

^/_matrix/client/(api/v1|r0|unstable)/rooms/.*/redact                               event_creator
^/_matrix/client/(api/v1|r0|unstable)/rooms/.*/send                                 event_creator
^/_matrix/client/(api/v1|r0|unstable)/rooms/.*/(join|invite|leave|ban|unban|kick)$  event_creator
^/_matrix/client/(api/v1|r0|unstable)/join/                                         event_creator
^/_matrix/client/(api/v1|r0|unstable)/profile/                                      event_creator

EOCONFIG

   # Some things can only be moved off master when using redis.
   if ( $self->{redis_host} ne '' ) {
      $haproxy_map .= <<'EOCONFIG';

^/_matrix/client/(api/v1|r0|unstable)/sendToDevice/          client_reader

EOCONFIG
   }

   return $haproxy_map
}

sub generate_haproxy_get_map
{
    return <<'EOCONFIG';
# pushrules should be here, but the tests seem to be racy.
# ^/_matrix/client/(api/v1|r0|unstable)/pushrules/            client_reader
^/_matrix/client/(api/v1|r0|unstable)/groups/               client_reader
^/_matrix/client/r0/user/[^/]*/account_data/                client_reader
^/_matrix/client/r0/user/[^/]*/rooms/[^/]*/account_data/    client_reader

^/_matrix/federation/v1/groups/                             federation_reader
EOCONFIG
}

1;
