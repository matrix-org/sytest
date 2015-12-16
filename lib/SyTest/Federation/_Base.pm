package SyTest::Federation::_Base;

use strict;
use warnings;

use mro 'c3';
use Protocol::Matrix qw( sign_json encode_base64_unpadded );

use Time::HiRes qw( time );

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( datastore )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   $self->next::method( %params );
}

sub datastore
{
   my $self = shift;
   return $self->{datastore};
}

sub server_name
{
   my $self = shift;
   return $self->{datastore}->server_name;
}

sub key_id
{
   my $self = shift;
   return $self->{datastore}->key_id;
}

# mutates the data
sub sign_data
{
   my $self = shift;
   my ( $data ) = @_;

   my $store = $self->{datastore};

   sign_json( $data,
      secret_key => $store->secret_key,
      origin     => $store->server_name,
      key_id     => $store->key_id,
   );
}

# returns a signed copy of the data
sub signed_data
{
   my $self = shift;
   my ( $orig ) = @_;

   $self->sign_data( my $copy = { %$orig } );

   return $copy;
}

sub get_key
{
   my $self = shift;
   my %params = @_;

   if( my $key = $self->{datastore}->get_key( %params ) ) {
      return Future->done( $key );
   }

   $self->_fetch_key( $params{server_name}, $params{key_id} )
      ->on_done( sub {
         my ( $key ) = @_;
         $self->{datastore}->put_key( %params, key => $key );
      });
}

sub time_ms
{
   return int( time() * 1000 );
}

1;
