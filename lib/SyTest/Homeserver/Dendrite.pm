# Copyright 2017 New Vector Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use Future;

package SyTest::Homeserver::Dendrite::Base;
use base qw( SyTest::Homeserver );

use Carp;
use POSIX qw( WIFEXITED WEXITSTATUS );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
       bindir pg_db pg_user pg_pass
   );

   defined $self->{bindir} or croak "Need a bindir";

   $self->{paths} = {};

   $self->SUPER::_init( $args );
}

sub start
{
   my $self = shift;

   my $hs_dir = $self->{hs_dir};

   # generate TLS key / cert
   # ...
   $self->{paths}{tls_cert} = "$hs_dir/server.crt";
   $self->{paths}{tls_key} = "$hs_dir/server.key";
   $self->{paths}{matrix_key} = "$hs_dir/matrix_key.pem";

   my %config = $self->_get_config;

   $self->{paths}{config} = $self->write_yaml_file( "dendrite.yaml" => \%config );

   return $self->_generate_keyfiles;
}

sub _check_db_config
{
   my $self = shift;
   my ( %config ) = @_;

   $config{type} eq "pg" or die "Dendrite can only run against postgres";

   return $self->SUPER::_check_db_config( @_ );
}

sub http_api_host
{
   my $self = shift;
   return $self->{bind_host};
}

# get the config to be written to the dendrite config file
sub _get_config
{
   my $self = shift;

   my %db_config = $self->_get_dbconfig(
      type => 'pg',
      args => {},
   );

   my $db_uri = sprintf('dbname=%s', $db_config{args}->{database});

   if( exists $db_config{args}->{user} ) {
      $db_uri .= sprintf( " user=%s", $db_config{args}->{user} );
   }

   if( exists $db_config{args}->{password} ) {
      $db_uri .= sprintf( " password=%s", $db_config{args}->{password} );
   }

   if( exists $db_config{args}->{host} ) {
      $db_uri .= sprintf( " host=%s", $db_config{args}->{host} );
   }

   if( exists $db_config{args}->{sslmode} ) {
      $db_uri .= sprintf( " sslmode=%s", $db_config{args}->{sslmode} );
   }

   return (
      version => 0,
      matrix => {
         server_name => $self->server_name,
         private_key => $self->{paths}{matrix_key},
         federation_certificates => [$self->{paths}{tls_cert}],
         registration_shared_secret => "reg_secret",

         $self->{recaptcha_config} ? (
            # here "true" gets written as a quote-less string, which in yaml is
            # a boolean value
            # Disabled until #592 is resolved
            # enable_registration_captcha => "true",
            recaptcha_siteverify_api => $self->{recaptcha_config}->{siteverify_api},
            recaptcha_public_key     => $self->{recaptcha_config}->{public_key},
            recaptcha_private_key    => $self->{recaptcha_config}->{private_key},
         ) : (),
      },

      media => {
         base_path => "media_store",
      },

      kafka => {
         topics => {
            output_room_event  => 'roomserverOutput',
            output_client_data => 'clientapiOutput',
            user_updates => 'userUpdates',
            output_typing_event => 'eduServerTypingOutput',
            output_send_to_device_event => 'eduServerSendToDeviceOutput',
         },
      },

      database => {
         # POSTGRES not set or is 0, use sqlite, which has separate .db files for each server
         map { ( ! defined $ENV{'POSTGRES'} || $ENV{'POSTGRES'} == '0') ?
         ($_ => "file:$self->{hs_dir}/" . $_ . ".db") :
         ($_ => $db_uri) } qw(
            account device media_api sync_api room_server server_key
            federation_sender public_rooms_api naffka appservice current_state
         ),
      },

      logging => [{
         type => 'file',
         level => 'debug',
         params => {
            path => "$self->{hs_dir}/dendrite-logs",
         },
      }],

      application_services => {
         config_files => $self->{app_service_config_files} ? $self->{app_service_config_files} : [],
      },
   );
}

# run the process to generate the key files
sub _generate_keyfiles
{
   my $self = shift;

   my @args = ();

   if( ! -f $self->{paths}{matrix_key} ) {
      push @args, '--private-key', $self->{paths}{matrix_key};
   }

   if( ! -f $self->{paths}{tls_cert} || ! -f $self->{paths}{tls_key} ) {
      push @args, '--tls-cert', $self->{paths}{tls_cert},
         '--tls-key', $self->{paths}{tls_key},
   }

   if( ! scalar @args ) {
      # nothing to do here.
      return Future->done;
   }

   $self->{output}->diag( "Generating key files" );

   return $self->_run_command(
      command => [
         $self->{bindir} . '/generate-keys',
         @args,
      ],
   )->on_done( sub {
      $self->{output}->diag( "Generated key files" );
   });
}


package SyTest::Homeserver::Dendrite::Monolith;
use base qw( SyTest::Homeserver::Dendrite::Base SyTest::Homeserver::ProcessManager );

use Carp;

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->SUPER::_init( $args );

   my $idx = $self->{hs_index};
   $self->{ports} = {
      monolith                 => main::alloc_port( "monolith[$idx]" ),
      monolith_unsecure        => main::alloc_port( "monolith[$idx].unsecure" ),
   };
}

sub configure
{
   my $self = shift;
   my %params = @_;

   $self->SUPER::configure( %params );
}

sub server_name
{
   my $self = shift;
   return $self->{bind_host} . ":" . $self->secure_port;
}

sub federation_port
{
   my $self = shift;
   return $self->secure_port;
}

sub secure_port
{
   my $self = shift;
   return $self->{ports}{monolith};
}

sub unsecure_port
{
   my $self = shift;
   return $self->{ports}{monolith_unsecure};
}

sub start
{
   my $self = shift;

   return $self->SUPER::start->then(
      $self->_capture_weakself( '_start_monolith' )
   );
}

sub _get_config
{
   my $self = shift;
   my %config = $self->SUPER::_get_config();

   $config{kafka}{use_naffka} = JSON::true;

   return %config;
}

# start the monolith binary, and return a future which will resolve once it is
# reachable.
sub _start_monolith
{
   my $self = shift;

   my $output = $self->{output};
   my $loop = $self->loop;

   $output->diag( "Starting monolith server" );
   my @command = (
      $self->{bindir} . '/dendrite-monolith-server',
      '--config', $self->{paths}{config},
      '--http-bind-address', $self->{bind_host} . ':' . $self->unsecure_port,
      '--https-bind-address', $self->{bind_host} . ':' . $self->secure_port,
      '--tls-cert', $self->{paths}{tls_cert},
      '--tls-key', $self->{paths}{tls_key},
   );

   push(@command, '-api') if $ENV{'API'} == '1';
   $output->diag( "Starting Dendrite with: @command" );

   return $self->_start_process_and_await_connectable(
      setup => [
         env => {
            LOG_DIR => $self->{hs_dir},
            DENDRITE_TRACE_SQL => $ENV{'DENDRITE_TRACE_SQL'},
            DENDRITE_TRACE_HTTP => $ENV{'DENDRITE_TRACE_HTTP'},
            DENDRITE_TRACE_INTERNAL => $ENV{'DENDRITE_TRACE_INTERNAL'},
         },
      ],
      command => [ @command ],
      connect_host => $self->{bind_host},
      connect_port => $self->secure_port,
   )->else( sub {
      die "Unable to start dendrite monolith: $_[0]\n";
   })->on_done( sub {
      $output->diag( "Started monolith server" );
   });
}

# override for Homeserver::kill_and_await_finish: delegate to
# ProcessManager::kill_and_await_finish
sub kill_and_await_finish
{
   my $self = shift;
   return $self->SyTest::Homeserver::ProcessManager::kill_and_await_finish();
}

1;
