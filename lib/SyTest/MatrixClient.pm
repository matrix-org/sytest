package SyTest::MatrixClient;

use strict;
use warnings;

# A silly subclass that remembers what port number it lives on
use base qw( Net::Async::Matrix );
Net::Async::Matrix->VERSION( '0.09' );

sub new
{
   my $class = shift;
   my %params = @_;

   my $port = delete $params{port};
   $params{server} = "$params{server}:$port";

   my %presence;

   my $self = $class->SUPER::new(
      %params,

      on_presence => sub {
         my ( $self, $user, %changes ) = @_;
         $presence{$user->user_id} = $user->presence;

         $changes{presence} and
            print qq(\e[1;36m[$port]\e[m >> "${\$user->displayname}" presence state now ${\$user->presence}\n);
      },
   );

   $self->{port} = $port;

   $self->{presence_cache} = \%presence;

   return $self;
}

sub port
{
   my $self = shift;
   return $self->{port};
}

sub cached_presence
{
   my $self = shift;
   my ( $user_id ) = @_;

   return defined $user_id
      ? $self->{presence_cache}{$user_id}
      : { %{ $self->{presence_cache} } };
}

1;
