package SyTest::MailServer;

use strict;
use warnings;
use Carp;

use SyTest::MailServer::Protocol;

use base qw( IO::Async::Listener );

=head1 NAME

C<SyTest::MailServer> - serve SMTP with C<IO::Async>

=head1 SYNOPSIS

 use SyTest::MailServer;
 use IO::Async::Loop;

 my $loop = IO::Async::Loop->new();

 my $mailserver = Net::Async::HTTP::Server->new(
    on_mail => sub {
       my $self = shift;
       my ( $to, $from, $data ) = @_;
    },
 );

 $loop->add( $mailserver );

 $mailserver->listen(
    addr => { family => "inet6", socktype => "stream", port => 2525 },
 )->get

 $loop->run;

=head1 DESCRIPTION

This module allows a program to respond asynchronously to SMTP requests, as
part of a program based on L<IO::Async>. An object in this class listens on a
single port and invokes the C<on_mail> callback or subclass method whenever
a mail is received over SMTP.

=cut

=head1 EVENTS

=head2 on_mail( $from, $to, $data )

Invoked when a new mail is received.

=head1 METHODS

As a small subclass of L<IO::Async::Listener>, this class does not provide many
new methods of its own. The superclass provides useful methods to control the
basic operation of this server.

Specifically, see the L<IO::Async::Listener/listen> method on how to actually
bind the server to a listening socket to make it accept requests.

=cut

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $args->{handle_class} = "SyTest::MailServer::Protocol";

   $self->SUPER::_init( $args );
}

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach ( qw( on_mail ) ) {
      $self->{$_} = delete $params{$_} if $params{$_};
   }

   $self->SUPER::configure( %params );
}

sub _add_to_loop
{
   my $self = shift;

   $self->can_event( "on_mail" ) or croak "Expected either a on_mail callback or an ->on_mail method";

   $self->SUPER::_add_to_loop( @_ );
}

sub on_accept
{
   my $self = shift;
   my ( $conn ) = @_;

   $conn->configure(
      on_closed => sub {
         my $conn = shift;
         $conn->on_closed();

         $conn->remove_from_parent;
      },
   );

   $self->add_child( $conn );

   $conn->send_reply( 220, "Sytest test server" );

   return $conn;
}

sub _received_mail
{
   my $self = shift;
   my ( $from, $to, $data ) = @_;

   $self->invoke_event( 'on_mail', $from, $to, $data );
}

1;

