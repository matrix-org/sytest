package SyTest::Federation::Datastore;

use strict;
use warnings;

use Carp;

use Protocol::Matrix qw( sign_event_json );

use List::Util 1.45 qw( uniq );
use Time::HiRes qw( time );

use SyTest::Federation::Room;
use SyTest::Federation::Protocol qw( hash_event id_for_event );

sub new
{
   my $class = shift;
   my %args = @_;

   return bless {
      %args,
      keys => {},

      next_event_id => 0,
      next_room_id => 0,

      room_aliases => {},
      rooms_by_id  => {},
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
   $event_id = $store->next_event_id( "suffix" )

Allocates and returns a new string event ID for a unique event on this server.

=cut

sub next_event_id
{
   my $self = shift;
   my ( $suffix ) = @_;

   my $localpart = "" . $self->{next_event_id}++;
   $localpart .= "_$suffix" if $suffix;

   return sprintf '$%s:%s', $localpart, $self->server_name;
}

=head2 get_event

   $event = $store->get_event( $event_id )

=head2 put_event

   $store->put_event( $event_id, $event )

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
   my ( $event_id, $event ) = @_;

   $self->{events_by_id}{ $event_id } = $event;
}

=head2 create_event

   $event = $store->create_event( [ room_version => ver, ] %fields );
   ( $event, $event_id ) = $store->create_event( [ room_version => ver, ] %fields );

Creates a new event with the given fields, signs it with L<sign_event>, stores
it using L<put_event> and returns it.

=cut

sub create_event
{
   my $self = shift;
   my %fields = @_;

   defined $fields{$_} or croak "Every event needs a '$_' field"
      for qw( type auth_events content depth prev_events room_id sender );

   my $room_version = delete $fields{room_version} // 1;
   my $event_id_suffix = delete $fields{event_id_suffix};

   my $event = {
      %fields,
      origin           => $self->server_name,
      origin_server_ts => JSON::number( int( time() * 1000 )),
   };

   my $event_id = $fields{event_id};
   if( $room_version eq '1' || $room_version eq '2' ) {
      if( not defined $event_id ) {
         # room v1/v2: assign an event id
         $event_id = $self->next_event_id( $event_id_suffix );
         $event->{event_id} = $event_id;
      }
      $self->sign_event( $event );
   } else {
      die "event with explicit event_id in room v$room_version"
         if defined $event_id;

      $self->sign_event( $event );
      $event_id = id_for_event( $event, $room_version );
   }

   $self->put_event( $event_id, $event );

   return $event unless wantarray;
   return ( $event, $event_id );
}

=head2 get_backfill_events

   @events = $store->get_backfill_events( start_at => \@ids, ... )

Returns a list of events, starting from the event(s) whose ID(s) are given by
the C<start_at> argument, and continuing backwards through their
C<prev_events> linkage. They are returned in a linearized order, most recent
first.

The following other named arguments affect the behaviour:

=over 4

=item limit => $limit

Gives the maximum number of events that should be returned.

=item stop_before => \@ids

Gives a list of event IDs that should not be entered into or returned (most
likely because the caller already has them). These events do not count towards
the overall count limit.

=back

=cut

sub get_backfill_events
{
   my $self = shift;
   my %params = @_;

   my $start_at = $params{start_at} or
      croak "Require 'start_at'";

   my $limit = $params{limit} or
      croak "Require 'limit'";

   my @event_ids = @$start_at;

   my %exclude = map { $_ => 1 } @{ $params{stop_before} // [] };

   my @events;
   while( @event_ids and @events < $limit ) {
      my $id = shift @event_ids;
      my $event = eval { $self->get_event( $id ) }
         or next;

      push @events, $event;

      push @event_ids, grep { !$exclude{$_} }
                       map { $_->[0] } @{ $event->{prev_events} };

      # Don't include this event if we encounter it again
      $exclude{$id} = 1;
   }

   return @events;
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

=head2 get_room

   $room = $store->get_room( $room_id )

Returns a L<SyTest::Federation::Room> having the given ID, if one exists, or
C<undef> if not.

=cut

sub get_room
{
   my $self = shift;
   my ( $room_id ) = @_;

   return $self->{rooms_by_id}{$room_id};
}

=head2 create_room

   $room = $store->create_room(
      creator => $creator,
      [ alias => $alias, ]
      [ room_version => $room_version, ]
   )

Creates a new L<SyTest::Federation::Room> instance with a new room ID and
stores it in the data store. It creates the initial room events using the
given C<creator> user ID. It associates the optional C<alias> if supplied.

=cut

sub create_room
{
   my $self = shift;
   my %args = @_;

   my $creator = $args{creator};
   my $room_version = $args{room_version} // 1;

   my $room = SyTest::Federation::Room->new(
      datastore => $self,
      room_version => $room_version,
   );

   $room->create_initial_events(
      creator => $creator,
   );

   $self->{rooms_by_id}{ $room->room_id } = $room;

   $self->{room_aliases}{ $args{alias} } = $room->room_id
      if $args{alias};

   return $room;
}

=head2 lookup_alias

   $room_id = $store->lookup_alias( $room_alias )

Returns the room ID associated with the given room alias, if one exists, or
C<undef> if not.

=cut

sub lookup_alias
{
   my $self = shift;
   my ( $room_alias ) = @_;

   return $self->{room_aliases}{$room_alias};
}

1;
