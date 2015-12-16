package SyTest::Federation::Datastore;

use strict;
use warnings;

use Carp;

use Protocol::Matrix qw( sign_event_json );

use List::MoreUtils qw( uniq );
use Time::HiRes qw( time );

sub new
{
   my $class = shift;
   my %args = @_;

   return bless {
      %args,
      keys => {},

      next_event_id => 0,
      next_room_id => 0,
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

Return the public or secret halves of the signing key of the local homeserver.

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

Accessor and mutator for remote homeserver federation key storage.

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

=head2 create_event

   $event = $store->create_event( %fields )

Creates a new event with the given fields, signs it with L<sign_event>, stores
it using L<put_event> and returns it.

=cut

sub create_event
{
   my $self = shift;
   my %fields = @_;

   defined $fields{$_} or croak "Every event needs a '$_' field"
      for qw( type auth_events content depth prev_events room_id sender );

   if( defined $fields{state_key} ) {
      defined $fields{$_} or croak "Every state event needs a '$_' field"
         for qw( prev_state );
   }

   my $event = {
      %fields,

      event_id         => $self->next_event_id,
      origin           => $self->server_name,
      origin_server_ts => int( time() * 1000 ),
   };

   $self->sign_event( $event );
   $self->put_event( $event );

   return $event;
}

=head2 get_auth_chain_events

   @events = $store->get_auth_chain_events( @event_ids )

Returns a list of every event in the (recursive) authentication chain leading
up to the events with the given ID(s).

=cut

sub get_auth_chain_events
{
   my $self = shift;
   my @event_ids = @_;

   my %events_by_id = map { $_ => $self->get_event( $_ ) } @event_ids;

   my @all_event_ids = @event_ids;

   while( @event_ids ) {
      my $event = $events_by_id{shift @event_ids};

      my @auth_ids = map { $_->[0] } @{ $event->{auth_events} };

      foreach my $id ( @auth_ids ) {
         next if $events_by_id{$id};

         $events_by_id{$id} = $self->get_event( $id );
         push @event_ids, $id;
      }

      # Keep the list in a linearised causality order
      @all_event_ids = uniq( @auth_ids, @all_event_ids );
   }

   return @events_by_id{ @all_event_ids };
}

=head2 next_room_id

   $room_id = $store->next_room_id

Allocates and returns a new string room ID for a unique room.

=cut

sub next_room_id
{
   my $self = shift;
   return sprintf "!%d:%s", $self->{next_room_id}++, $self->server_name;
}

1;
