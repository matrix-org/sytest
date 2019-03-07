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

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
      synapse_dir extra_args python coverage
   );

   $self->{paths} = {};
   $self->{dendron} = '';

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

   my %db_config = $self->_get_dbconfig(
      type => 'sqlite',
      args => {
         database => ":memory:", #"$hs_dir/homeserver.db",
      },
   );

   my $db_type = $db_config{type};

   # map sytest db args onto synapse db args
   my %synapse_db_config;
   if( $db_type eq "pg" ) {
      %synapse_db_config = (
         name => 'psycopg2',
         args => $db_config{args},
      );
   }
   else {
      # must be sqlite
      %synapse_db_config = (
         name => 'sqlite3',
         args => $db_config{args},
      );
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
   my $log_config_file = "$hs_dir/log.config";

   my $macaroon_secret_key = "secret_$port";
   my $registration_shared_secret = "reg_secret";

   my $config_path = $self->{paths}{config} = $self->write_yaml_file( "config.yaml" => {
        server_name => $self->server_name,
        log_file => "$log",
        ( -f $log_config_file ) ? ( log_config => $log_config_file ) : (),
        tls_certificate_path => "$cwd/keys/tls-selfsigned.crt",
        tls_private_key_path => "$cwd/keys/tls-selfsigned.key",
        tls_dh_params_path => "$cwd/keys/tls.dh",
        use_insecure_ssl_client_just_for_testing_do_not_use => 1,
        rc_messages_per_second => 1000,
        rc_message_burst_count => 1000,
        rc_registration_requests_per_second => 1000,
        rc_registration_request_burst_count => 1000,
        enable_registration => "true",
        database => \%synapse_db_config,
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

        # we reduce the number of bcrypt rounds to make generating users
        # faster, but note that python's bcrypt complains if rounds < 4,
        # so this is effectively the minimum.
        bcrypt_rounds => 4,

        # If we're using dendron-style split workers, we need to disable these
        # things in the main process
        start_pushers         => ( not $self->{dendron} ),
        notify_appservices    => ( not $self->{dendron} ),
        send_federation       => ( not $self->{dendron} ),
        update_user_directory => ( not $self->{dendron} ),
        enable_media_repo     => ( not $self->{dendron} ),

        url_preview_enabled => "true",
        url_preview_ip_range_blacklist => [],

        media_store_path => "$hs_dir/media_store",
        uploads_path => "$hs_dir/uploads_path",

        user_agent_suffix => "homeserver[". $self->{hs_index} . "]",

        $self->{recaptcha_config} ? (
           recaptcha_siteverify_api => $self->{recaptcha_config}->{siteverify_api},
           recaptcha_public_key     => $self->{recaptcha_config}->{public_key},
           recaptcha_private_key    => $self->{recaptcha_config}->{private_key},
        ) : (),

        map {
           defined $self->{$_} ? ( $_ => $self->{$_} ) : ()
        } qw(
           cas_config
           app_service_config_files
        ),
   } );

   $self->{paths}{log} = $log;

   {
      # create or truncate
      open my $tmph, ">", $log or die "Cannot open $log for writing - $!";
      foreach my $suffix ( qw( appservice media_repository federation_reader synchrotron federation_sender client_reader user_dir event_creator ) ) {
         open my $tmph, ">", "$log.$suffix" or die "Cannot open $log.$suffix for writing - $!";
      }
   }

   my @synapse_command = ( $self->{python} );

   if( $self->{coverage} ) {
      # Ensures that even --generate-config has coverage reports. This is intentional
      push @synapse_command,
         "-m", "coverage", "run", "-p", "--source=$self->{synapse_dir}/synapse";
   }

   push @synapse_command,
      "-m", "synapse.app.homeserver",
      "--config-path" => $config_path,
      "--server-name" => $self->server_name;

   $output->diag( "Generating config for port $port" );

   my @config_command = (
      @synapse_command, "--generate-config", "--report-stats=no",
   );

   my @command = (
      $self->wrap_synapse_command( @synapse_command ),
      @{ $self->{extra_args} },
   );

   my $env = {
      "PATH" => $ENV{PATH},
      "PYTHONDONTWRITEBYTECODE" => "Don't write .pyc files",
   };

   my $loop = $self->loop;

   my $started_future = $loop->new_future;

   $output->diag(
      "Creating config for server $hs_index with command "
         . join( " ", @config_command ),
   );

   $loop->open_process(
      setup => [ env => $env ],
      command => [ @config_command ],

      on_finish => sub {
         my ( $proc, $exitcode ) = @_;

         if( $exitcode != 0 ) {
            $started_future->fail( "Server failed to generate config: exitcode " . ( $exitcode >> 8 ));
            return
         }

         $output->diag(
            "Starting server $hs_index for port $port with command "
               . join( " ", @command ),
         );

         $self->add_child(
            $self->{proc} = IO::Async::Process->new(
               setup => [ env => $env ],

               command => \@command,

               on_finish => $self->_capture_weakself( 'on_finish' ),
            )
         );

         $self->adopt_future(
            $self->await_connectable( $bind_host, $self->_start_await_port )->then( sub {
               $started_future->done;
            })
         );

         $self->open_logfile;
      }
   );

   return $started_future;
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
         tls          => 0,
         resources    => [{
            names => [ "client", "federation", "replication", "metrics" ], compress => 0
         }]
      }
   }

   if( my $replication_tcp_port = $self->{ports}{synapse_replication_tcp} ) {
      push @listeners, {
         type         => "replication",
         port         => $replication_tcp_port,
         bind_address => $bind_host,
         tls          => 0,
      }
   }

   return @listeners,
      {
         type         => "metrics",
         port         => $self->{ports}{synapse_metrics},
         bind_address => $bind_host,
         tls          => 0,
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
   return 0 if !$self->{proc};
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

sub kill_and_await_finish
{
   my $self = shift;

   return $self->SUPER::kill_and_await_finish->then( sub {

      # skip this if the process never got started.
      return Future->done unless $self->pid;

      $self->{output}->diag( "Killing ${\ $self->pid }" );

      $self->kill( 'INT' );

      return Future->needs_any(
         $self->await_finish,

         $self->loop->delay_future( after => 30 )->then( sub {
            print STDERR "Timed out waiting for ${\ $self->pid }; sending SIGKILL\n";
            $self->kill( 'KILL' );
            Future->done;
         }),
        );
   });
}

sub on_finish
{
   my $self = shift;
   my ( $process, $exitcode ) = @_;

   my $hs_index = $self->{hs_index};

   say $self->pid . " stopped";

   my $port = $self->{ports}{synapse};

   if( $exitcode > 0 ) {
      if( WIFEXITED($exitcode) ) {
         warn "Main homeserver process for server $hs_index exited " . WEXITSTATUS($exitcode) . "\n";
      }
      else {
         warn "Main homeserver process for server $hs_index failed - code=$exitcode\n";
      }

      print STDERR "\e[1;35m[server $port}]\e[m: $_\n"
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

package SyTest::Homeserver::Synapse::ViaDendron;
use base qw( SyTest::Homeserver::Synapse );

use Carp;

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->SUPER::_init( @_ );

   $self->{dendron} = delete $args->{dendron_binary};

   my $idx = $self->{hs_index};
   $self->{ports}{dendron} = main::alloc_port( "dendron[$idx]" );
}

sub _check_db_config
{
   my $self = shift;
   my ( %config ) = @_;

   $config{type} eq "pg" or die "Dendron can only run against postgres";

   return $self->SUPER::_check_db_config( @_ );
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
         "worker_app"              => "synapse.app.pusher",
         "worker_log_file"         => "$log.pusher",
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
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
      } );

      push @command, "--pusher-config" => $pusher_config_path;
   }

   {
      my $appservice_config_path = $self->write_yaml_file( "appservice.yaml" => {
         "worker_app"              => "synapse.app.appservice",
         "worker_log_file"         => "$log.appservice",
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
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
      } );

      push @command, "--appservice-config" => $appservice_config_path;
   }

   {
      my $federation_sender_config_path = $self->write_yaml_file( "federation_sender.yaml" => {
         "worker_app"              => "synapse.app.federation_sender",
         "worker_log_file"         => "$log.federation_sender",
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
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
      } );

      push @command, "--federation-sender-config" => $federation_sender_config_path;
   }

   {
      my $synchrotron_config_path = $self->write_yaml_file( "synchrotron.yaml" => {
         "worker_app"              => "synapse.app.synchrotron",
         "worker_log_file"         => "$log.synchrotron",
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
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
      } );

      push @command,
         "--synchrotron-config" => $synchrotron_config_path,
         "--synchrotron-url" => "http://$bind_host:$self->{ports}{synchrotron}";
   }

   {
      my $federation_reader_config_path = $self->write_yaml_file( "federation_reader.yaml" => {
         "worker_app"              => "synapse.app.federation_reader",
         "worker_log_file"         => "$log.federation_reader",
         "worker_replication_host" => "$bind_host",
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
      } );

      push @command,
         "--federation-reader-config" => $federation_reader_config_path,
         "--federation-reader-url" => "http://$bind_host:$self->{ports}{federation_reader}";
   }

   {
      my $media_repository_config_path = $self->write_yaml_file( "media_repository.yaml" => {
         "worker_app"              => "synapse.app.media_repository",
         "worker_log_file"         => "$log.media_repository",
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
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
      } );

      push @command,
         "--media-repository-config" => $media_repository_config_path,
         "--media-repository-url" => "http://$bind_host:$self->{ports}{media_repository}";
   }

   {
      my $client_reader_config_path = $self->write_yaml_file( "client_reader.yaml" => {
         "worker_app"              => "synapse.app.client_reader",
         "worker_log_file"         => "$log.client_reader",
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
         "worker_listeners"        => [
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

   {
      my $user_dir_config_path = $self->write_yaml_file( "user_dir.yaml" => {
         "worker_app"              => "synapse.app.user_dir",
         "worker_log_file"         => "$log.user_dir",
         "worker_replication_host" => "$bind_host",
         "worker_replication_port" => $self->{ports}{synapse_replication_tcp},
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
      } );

      push @command,
         "--user-directory-config" => $user_dir_config_path,
         "--user-directory-url" => "http://$bind_host:$self->{ports}{user_dir}";
   }

   {
      my $event_creator_config_path = $self->write_yaml_file( "event_creator.yaml" => {
         "worker_app"                   => "synapse.app.event_creator",
         "worker_log_file"              => "$log.event_creator",
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
      } );

      push @command,
         "--event-creator-config" => $event_creator_config_path,
         "--event-creator-url" => "http://$bind_host:$self->{ports}{event_creator}";
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

use constant HAPROXY_BIN => $ENV{HAPROXY_BIN} // "/usr/sbin/haproxy";

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
      $self->{paths}{path_map_file} = $self->write_file( "path_map_file", $self->generate_haproxy_map );

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

EOCONFIG
}

sub generate_haproxy_map
{
    return <<'EOCONFIG';
^/_matrix/client/(v2_alpha|r0)/sync$            synchrotron
^/_matrix/client/(api/v1|v2_alpha|r0)/events$   synchrotron
# We need to catch global and per room, so just match based on ending.
^/_matrix/client/.*/initialSync$                synchrotron

^/_matrix/media/    media_repository

^/_matrix/federation/v1/event/                  federation_reader
^/_matrix/federation/v1/state/                  federation_reader
^/_matrix/federation/v1/state_ids/              federation_reader
^/_matrix/federation/v1/backfill/               federation_reader
^/_matrix/federation/v1/get_missing_events/     federation_reader
^/_matrix/federation/v1/publicRooms             federation_reader

^/_matrix/client/(api/v1|r0)/publicRooms$    client_reader

^/_matrix/client/(r0|unstable|v2_alpha)/user_directory/    user_dir

^/_matrix/client/(api/v1|r0|unstable)/rooms/.*/send      event_creator
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
