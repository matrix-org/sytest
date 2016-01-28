package SyTest::ApplicationService;

use strict;
use warnings;

sub new
{
   my $class = shift;
   my ( $info, $await_http, $await_event ) = @_;

   return bless {
      info       => $info,
      await_http => $await_http,
      await_event => $await_event,
   }, $class;
}

sub await_http_request
{
   my $self = shift;
   my ( $path, @args ) = @_;

   $self->{await_http}->( $self->{info}->path . $path, @args );
}

sub await_event
{
   my $self = shift;

   $self->{await_event}->( @_ );
}

1;
