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

package SyTest::HomeserverFactory;

# get the name of this implementation, by which it can be referenced with -I
sub name
{
   my $cls = "" . shift;
   $cls =~ s/^SyTest::HomeserverFactory:://;
   return $cls;
}

sub new
{
   my $class = shift;
   my %params = @_;

   my $self = bless {}, $class;

   $self->_init( \%params );

   return $self;
}

sub _init {}

1;
