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

   my $self = $class->SUPER::new( %params );

   $self->{port} = $port;

   return $self;
}

sub port
{
   my $self = shift;
   return $self->{port};
}

1;
