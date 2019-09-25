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

package SyTest::Homeserver::Manual;
use base qw( SyTest::Homeserver );

use Carp;

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw (
       host
       secure_port
       unsecure_port
       server_name
   )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   foreach (qw ( host server_name )) {
      defined $self->{$_} or croak "Need a $_";
   }

   if ( ! defined $self->{secure_port} && ! defined $self->{unsecure_port} ) {
      croak "Need either a secure_port or an unsecure_port";
   }

   $self->SUPER::configure( %params );
}

sub server_name
{
   my $self = shift;

   return $self->{server_name};
}

sub http_api_host
{
   my $self = shift;
   return $self->{host};
}

sub federation_port
{
   my $self = shift;
   return $self->secure_port;
}

sub secure_port
{
   my $self = shift;

   return $self->{secure_port};
}

sub unsecure_port
{
   my $self = shift;

   return $self->{unsecure_port};
}

sub start
{
   my $self = shift;

   return Future->done;
}

sub pid
{
   return 0;
}


1;
