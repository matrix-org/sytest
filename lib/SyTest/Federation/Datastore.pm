package SyTest::Federation::Datastore;

use strict;
use warnings;

sub new
{
   my $class = shift;
   return bless {
      keys => {},
   }, $class;
}

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
