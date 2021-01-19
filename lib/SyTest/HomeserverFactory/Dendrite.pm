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

require SyTest::Homeserver::Dendrite;

package SyTest::HomeserverFactory::Dendrite;
use base qw( SyTest::HomeserverFactory );

sub _init
{
   my $self = shift;

   $self->{args} = {
      bindir => "../dendrite/bin",
      print_output  => 0,
   };

   $self->SUPER::_init( @_ );
}

sub implementation_name
{
   return "dendrite";
}

sub get_options
{
   my $self = shift;

   return (
      'd|dendrite-binary-directory=s' => \$self->{args}{bindir},
      'S|server-log+' => \$self->{args}{print_output},
      $self->SUPER::get_options(),
   );
}

sub print_usage
{
   print STDERR <<EOF
   -d, --dendrite-binary-directory DIR  - path to the directory containing the
                                          dendrite binaries
EOF
}

sub create_server
{
   die 'polylith Dendrite not yet implemented';
}

package SyTest::HomeserverFactory::Dendrite::Monolith;
use base qw( SyTest::HomeserverFactory::Dendrite );

sub _init
{
   my $self = shift;
   $self->{impl} = "SyTest::Homeserver::Dendrite::Monolith";

   $self->SUPER::_init( @_ );
}

sub create_server
{
   my $self = shift;
   my %params = ( @_, %{ $self->{args}} );

   return $self->{impl}->new( %params );
}

1;
