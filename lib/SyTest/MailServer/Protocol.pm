package SyTest::MailServer::Protocol;

use strict;
use warnings;
use base qw( IO::Async::Stream );

my $CRLF = "\x0d\x0a";

sub on_read
{
   my $self = shift;
   my ( $buffref, $eof ) = @_;

   return 0 if $eof;
   return 0 unless $$buffref =~ s/^(.*?$CRLF)//s;

   my ( $verb, $params ) = $self->tokenize_command( $1 );
   return $self->process_command( $verb, $params );
} 

sub on_closed
{
   my $self = shift;
}

sub tokenize_command {
    my ( $self, $line ) = @_;
    $line =~ s/\r?\n$//s;
    $line =~ s/^\s+|\s+$//g;
    my ( $verb, $params ) = split ' ', $line, 2;
    $verb = uc($verb) if defined($verb);
    return ( $verb, $params );
}

sub process_command
{
   my $self = shift;
   my ( $verb, $params ) = @_;

   $self->debug_printf( "COMMAND %s %s", $verb, $params );

   if( my $code = $self->can( "on_" . $verb )) {
      return $code->( $self, $params ) // 1;
   } else {
      $self->send_reply( 500, 'Syntax error: unrecognized command' );
      return 1;
   }
}

sub send_reply
{
   my ( $self ) = shift;
   my ( $code, $msg ) = @_;

   $self->write( "$code $msg\r\n" );
}

sub on_HELO
{
   my ( $self ) = shift;
   my ( $params ) = @_;

   $self->send_reply( 250, "hi" );
}

sub on_MAIL
{
   my ( $self ) = shift;
   my ( $params ) = @_;

   if( defined $self->{mail_from} ) {
      $self->send_reply( 503, 'Bad sequence of commands' );
      return;
   }

   unless ( $params =~ s/^from:\s*//i ) {
      $self->send_reply( 501, 'Syntax error in parameters or arguments' );
      return;
   }

   $self->{mail_from} = $params;
   $self->send_reply( 250, "ok" );
}

sub on_RCPT
{
   my ( $self ) = shift;
   my ( $params ) = @_;

   if( defined $self->{rcpt_to} ) {
      $self->send_reply( 503, 'Bad sequence of commands' );
      return;
   }

   unless ( $params =~ s/^to:\s*//i ) {
      $self->send_reply( 501, 'Syntax error in parameters or arguments' );
      return;
   }

   $self->{rcpt_to} = $params;
   $self->send_reply( 250, "ok" );
}

sub on_DATA
{
   my ( $self ) = shift;
   my ( $params ) = @_;

   if( not defined $self->{rcpt_to} or not defined $self->{mail_from} ) {
      $self->send_reply( 503, 'Bad sequence of commands' );
      return;
   }

   if ( $params ) {
      $self->send_reply( 501, 'Syntax error in parameters or arguments' );
      return;
   }

   $self->send_reply( 354, "send message" );

   return sub {
      my ( undef, $buffref, $eof ) = @_;
      return 0 unless $$buffref =~ s/(^.*$CRLF)\.$CRLF//s;

      $self->parent->_received_mail( $self->{mail_from}, $self->{rcpt_to}, $1 );
      $self->send_reply( 250, "ok" );
      $self->{rcpt_to} = undef;
      $self->{mail_from} = undef;
      return undef;
   }
}

1;

