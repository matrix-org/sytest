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

   $self->{args} = {
      synapse_dir   => "../synapse",
      python        => "python",
      coverage      => 0,
   };

   $self->SUPER::_init( @_ );
}

sub get_options
{
   my $self = shift;

   return (
      'd|synapse-directory=s' => \$self->{args}{synapse_dir},
      'python=s' => \$self->{args}{python},
      'coverage+' => \$self->{args}{coverage},
      $self->SUPER::get_options(),
   );
}

sub print_usage
{
   print STDERR <<EOF
   -d, --synapse-directory DIR  - path to the checkout directory of synapse

       --python PATH            - path to the 'python' binary

       --coverage               - generate code coverage stats for synapse
EOF
}

sub create_server
{
   my $self = shift;
   my %params = ( @_, %{ $self->{args}} );
   return $self->{impl}->new( %params );
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
