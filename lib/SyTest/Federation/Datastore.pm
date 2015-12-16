package SyTest::Federation::Datastore;

use strict;
use warnings;

sub new
{
   my $class = shift;
   my %args = @_;

   return bless {
      %args,
      keys => {},
   }, $class;
}

=head2 server_name

   $name = $store->server_name

Returns the federation name of the server

=cut

sub server_name { $_[0]->{server_name} }

=head2 key_id

   $id = $store->key_id

Returns the key ID of the signing key the server is currently using

=cut

sub key_id { $_[0]->{key_id} }

=head2 public_key

   $key = $store->public_key

=head2 secret_key

   $key = $store->secret_key

Return the public or secret halves of the signing key the server is currently
using

=cut

sub public_key { $_[0]->{public_key} }
sub secret_key { $_[0]->{secret_key} }

=head2 get_key

   $key = $store->get_key( server_name => $name, key_id => $id )

=head2 put_key

   $store->put_key( server_name => $name, key_id => $id, key => $key )

Accessor and mutator for federation key storage

=cut

sub get_key
{
   my $self = shift;
   my %params = @_;

   # hashes have keys. not the same as crypto keys. Grr.
   my $hk = "$params{server_name}:$params{key_id}";

   return $self->{keys}{$hk};
}

sub put_key
{
   my $self = shift;
   my %params = @_;

   # hashes have keys. not the same as crypto keys. Grr.
   my $hk = "$params{server_name}:$params{key_id}";

   $self->{keys}{$hk} = $params{key};
}

1;
