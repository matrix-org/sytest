package SyTest::Federation::_Base;

use strict;
use warnings;

use mro 'c3';
use Protocol::Matrix qw( sign_json );

sub configure
{
   my $self = shift;
   my %params = @_;

   foreach (qw( federation_params keystore )) {
      $self->{$_} = delete $params{$_} if exists $params{$_};
   }

   $self->next::method( %params );
}

sub server_name
{
   my $self = shift;
   return $self->{federation_params}->server_name;
}

sub key_id
{
   my $self = shift;
   return $self->{federation_params}->key_id;
}

sub sign_data
{
   my $self = shift;
   my ( $data ) = @_;

   my $fedparams = $self->{federation_params};

   sign_json( $data,
      secret_key => $fedparams->secret_key,
      origin     => $fedparams->server_name,
      key_id     => $fedparams->key_id,
   );
}

sub get_key
{
   my $self = shift;
   my %params = @_;

   # hashes have keys. not the same as crypto keys. Grr.
   my $hk = "$params{server_name}:$params{key_id}";

   $self->{keystore}{$hk} //= $self->_fetch_key( $params{server_name}, $params{key_id} );
}

1;
