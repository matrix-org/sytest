package SyTest::ApplicationService;

use strict;
use warnings;

sub new
{
   my $class = shift;
   my ( $info, $await_http ) = @_;

   return bless {
      info       => $info,
      await_http => $await_http,
   }, $class;
}

sub await_http_request
{
   my $self = shift;
   my ( $path, @args ) = @_;

   $self->{await_http}->( $self->{info}->path . $path, @args );
}

1;
