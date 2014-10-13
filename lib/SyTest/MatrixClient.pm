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

# TODO: NaMatrix really ought to make a way to allow this sort of subclassing
sub _make_room
{
   my $self = shift;

   my $old_new = Net::Async::Matrix::Room->can( 'new' );
   local *Net::Async::Matrix::Room::new = sub {
      if( $_[0] eq "Net::Async::Matrix::Room" ) {
         shift;
         return SyTest::MatrixClient::Room->new( @_ );
      }
      else {
         return $old_new->( @_ );
      }
   };

   return $self->SUPER::_make_room( @_ );
}

package SyTest::MatrixClient::Room {
   use base qw( Net::Async::Matrix::Room );

   sub _init
   {
      my $self = shift;
      my ( $params ) = @_;

      $self->{messages} = \my @messages;

      $params->{on_message} = sub {
         my ( $self, $member, $content ) = @_;
         push @messages, [ $member, $content ];
      };

      $self->SUPER::_init( $params );
   }

   sub last_message
   {
      my $self = shift;
      return $self->{messages}[-1];
   }
}

1;
