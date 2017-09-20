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

require SyTest::Homeserver::Synapse;

package SyTest::HomeserverFactory::Synapse;
use base qw( SyTest::HomeserverFactory );

sub _init
{
   my $self = shift;
   $self->{impl} = "SyTest::Homeserver::Synapse::Direct";
   $self->SUPER::_init( @_ );
}

sub create_server
{
   my $self = shift;
   return $self->{impl}->new( @_ );
}


package SyTest::HomeserverFactory::Synapse::ViaDendron;
use base qw( SyTest::HomeserverFactory::Synapse );

sub _init
{
   my $self = shift;
   $self->{impl} = "SyTest::Homeserver::Synapse::ViaDendron";
   $self->SUPER::_init( @_ );
}


package SyTest::HomeserverFactory::Synapse::ViaHaproxy;
use base qw( SyTest::HomeserverFactory::Synapse::ViaDendron );

sub _init
{
   my $self = shift;
   $self->{impl} = "SyTest::Homeserver::Synapse::ViaHaproxy";
   $self->SUPER::_init( @_ );
}

1;
