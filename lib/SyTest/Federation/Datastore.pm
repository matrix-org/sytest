package SyTest::Federation::Datastore;

use strict;
use warnings;

use Carp;

use Protocol::Matrix qw( sign_event_json );

sub new
{
   my $class = shift;
   my %args = @_;

   return bless {
      %args,
      keys => {},

      next_event_id => 0,
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

=head2 sign_event

   $store->sign_event( $event )

Applies the event signing algorithm to the given event, adding the result to
the C<signatures> key.

=cut

sub sign_event
{
   my $self = shift;
   my ( $event ) = @_;

   sign_event_json( $event,
      secret_key => $self->secret_key,
      origin     => $self->server_name,
      key_id     => $self->key_id,
   );
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

=head2 next_event_id

   $event_id = $store->next_event_id

Allocates and returns a new string event ID for a unique event on this server.

=cut

sub next_event_id
{
   my $self = shift;
   return sprintf "\$%d:%s", $self->{next_event_id}++, $self->server_name;
}

=head2 get_event

   $event = $store->get_event( $event_id )

=head2 put_event

   $store->put_event( $event )

Accessor and mutator for event storage

=cut

sub get_event
{
   my $self = shift;
   my ( $event_id ) = @_;

   my $event = $self->{events_by_id}{$event_id} or
      croak "$self has no event id '$event_id'";

   return $event;
}

sub put_event
{
   my $self = shift;
   my ( $event ) = @_;

   $self->{events_by_id}{ $event->{event_id} } = $event;
}

1;
