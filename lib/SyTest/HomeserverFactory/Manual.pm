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

require SyTest::Homeserver::Manual;

package SyTest::HomeserverFactory::Manual;
use base qw( SyTest::HomeserverFactory );

sub _init
{
   my $self = shift;

   $self->{servers} = [];

   $self->SUPER::_init( @_ );
}

sub get_options
{
   my $self = shift;

   return (
      'L|server=s' => \@{ $self->{servers} },
      $self->SUPER::get_options(),
   );
}

sub print_usage
{
   print STDERR <<EOF
   -L, --server URI             - Server name and URI to connect to, in the format
                                  "example.com=https://localhost:8448". If server
                                  name not given, e.g. "https://localhost:8448"
                                  then the server name is assumed to be the host
                                  and port. Can be specified multiple times to
                                  point at multiple running servers.
EOF
}

sub create_server
{
   my $self = shift;
   my %params = ( @_ );

   my $server = shift @{ $self->{servers} };
   if( !defined $server ) {
      die "can only create one server with -I Manual\n";
   }

   my ($location, $server_name) = reverse(split(/=/, $server));

   my ( $https, $host, $port ) =
      ( $location =~ m#^http(s)?://([^:/]+)(?::([0-9]+))?$# ) or
      die 'unable to parse location';

   if( !defined $port ) {
      $port = $https ? 443 : 80;
   }

   $params{host} = $host;
   if( $https ) {
      $params{secure_port} = $port;
   } else {
      $params{unsecure_port} = $port;
   }

   $params{server_name} = ${server_name} // "$host:$port";

   return SyTest::Homeserver::Manual->new( %params );
}

1;
