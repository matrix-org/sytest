package SyTest::Federation::Room;

use strict;
use warnings;

use Carp;

use List::Util qw( max );
use List::UtilsBy qw( extract_by );

use SyTest::Federation::Protocol;

=head1 NAME

C<SyTest::Federation::Room> - represent a single Room instance

=head1 CONSTRUCTOR

=cut

=head2 new

   $room = SyTest::Federation::Room->new(
      room_id => $room_id,
      datastore => $store,
      [ room_version => $room_version, ]
   )

Constructs a new Room instance, initially blank containing no state or events.

C<room_id> may be left undefined, and a new room ID will be allocated from the
datastore if so.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $datastore = $args{datastore} or
      croak "Require a 'datastore'";

   my $room_id = $args{room_id} // $datastore->next_room_id;
   my $room_version = $args{room_version} // 1;

   return bless {
      room_id   => $room_id,
      datastore => $datastore,
      room_version => $room_version,

      current_state => {},
      prev_events => [],
   }, $class;
}

=head1 METHODS

=head2 make_event_refs

   $refs = $room->make_event_refs( $event1, $event2, ... );

Given a set of events, create a list of either (event_id, hash) tuples or
straight event_ids, suitable for inclusion in prev_events or auth_events for
this room.

Each C<$event> param should be a HASH reference for an event.

Returns an ARRAY reference.

=cut

sub make_event_refs
{
   my $self = shift;
   my @events = @_;

   if ( $self->room_version eq "1" || $self->room_version eq "2" ) {
      # room versions 1 and 2 use [ event_id, hash ] pairs.
      return [ map { [ $_->{event_id}, $_->{hashes} ] } @_ ];
   } else {
      # other room versions just use event ids.
      return [ map { $self->id_for_event( $_ ) } @_ ];
   }
}

=head2 event_ids_from_refs

   $event_ids = $room->event_ids_from_refs( [ $ref1, $ref2 ] );

Performs the reverse operation to C<make_event_refs>: unpacks a C<prev_events>
or C<auth_events> list and returns an ARRAY ref of event ids.

=cut

sub event_ids_from_refs
{
   my $self = shift;
   my ( $event_refs ) = @_;

   my @event_ids;
   if ( $self->room_version eq "1" || $self->room_version eq "2" ) {
      @event_ids = map { $_->[0] } @$event_refs;
      return \@event_ids;
   }

   return $event_refs;
}

=head2 room_id

   $room_id = $room->room_id

Accessor to return the room ID.

=cut

sub room_id
{
   return $_[0]->{room_id};
}


=head2 room_version

    $room_version = $room->room_version;

Accessor to return the room version.

=cut

sub room_version
{
   return $_[0]->{room_version};
}


=head2 next_depth

   $depth = $room->next_depth

Returns the depth value that the next inserted event should have. This will be
1 more than the maximum depth of any of the events currently known for the
C<prev_events> field.

=cut

sub next_depth
{
   my $self = shift;

   if( @{ $self->{prev_events} } ) {
      return 1 + max( map { $_->{depth} } @{ $self->{prev_events} } );
   }
   else {
      return 0;
   }
}

=head2 create_initial_events

   $room->create_initial_events( creator => $creator )

Convenience helper method to create all the initial state events required at
room creation time. It supplies the C<m.room.create> event with the given
C<$creator> user ID as the room's creator, the C<m.room.member> event for this
user, and a C<m.room.join_rules> to set the room join permission as C<public>.

=cut

sub create_initial_events
{
   my $self = shift;
   my %args = @_;

   my $creator = $args{creator} or
      croak "Require a 'creator'";

   my $room_version = $args{room_version} // (
      $self->room_version == 1 ? undef : $self->room_version
   );

   $self->create_and_insert_event(
      type => "m.room.create",

      content     => {
         creator => $creator,
         defined( $room_version ) ? ( room_version => $room_version ) : (),
      },
      sender      => $creator,
      state_key   => "",
   );

   $self->create_and_insert_event(
      type => "m.room.member",

      content     => { membership => "join" },
      sender      => $creator,
      state_key   => $creator,
   );

   $self->create_and_insert_event(
      type => "m.room.join_rules",

      content     => { join_rule => "public" },
      sender      => $creator,
      state_key   => "",
   );
}

=head2 create_event

   $event = $room->create_event( %fields );

or:

   ( $event, $event_id ) = $room->create_event( %fields );

Constructs a new event in the room. This helper also fills in the C<depth>,
C<prev_events> and C<auth_events> lists if they are absent from C<%fields>,
meaning the caller does not have to. Any values that are passed are used
instead, even if they are somehow invalid - this allows callers to construct
intentionally-invalid events for testing purposes.

=cut

sub create_event
{
   my $self = shift;
   my %fields = @_;

   my @auth_events = grep { defined } (
      $self->get_current_state_event( "m.room.create" ),
      $self->get_current_state_event( "m.room.join_rules" ),
      $self->get_current_state_event( "m.room.power_levels" ),
      $self->get_current_state_event( "m.room.member", $fields{sender} ),
   );
   $fields{auth_events} //= $self->make_event_refs( @auth_events ),

   $fields{depth} //= JSON::number($self->next_depth);

   $fields{prev_events} //= $self->make_event_refs( @{ $self->{prev_events} } );

   return $self->{datastore}->create_event(
      room_version => $self->room_version,
      room_id => $self->room_id,
      %fields,
   );
}

=head2 create_and_insert_event

   $event = $room->create_and_insert_event( %fields );

or:

   ( $event, $event_id ) = $room->create_and_insert_event( %fields );

Constructs a new event via C<create_event>, updates the current state, if it is a
state event, and records the event as the room's next prev_event.

=cut

sub create_and_insert_event
{
   my $self = shift;
   my %fields = @_;

   my ( $event, $event_id ) = $self->create_event( %fields );

   $self->insert_outlier_event( $event );

   $self->{prev_events} = [ $event ];

   return $event unless wantarray;
   return ( $event, $event_id );
}

=head2 insert_event

   $room->insert_event( $event );

Inserts a new event into the database, updating the room's view of the forward
extremities (i.e. event IDs to use as the prev events of the the next
generated event).

=cut

sub insert_event
{
   my $self = shift;
   my ( $event ) = @_;

   $self->insert_outlier_event( $event );

   my $prev_events = $self->{prev_events};
   push @$prev_events, $event;

   # Remove from $self->{prev_events} any event IDs that are now recursively
   # implied by this new event.
   my @event_ids_to_remove = @{ $self->event_ids_from_refs( $event->{prev_events} ) };
   my %to_remove = map { $_ => 1 } @event_ids_to_remove;
   extract_by { $to_remove{ $self->id_for_event($_) } } @$prev_events;
}


=head2 insert_outlier_event

   $room->insert_outlier_event( $event );

Inserts a new event into the database, *without* updating the room's forward
extremities (i.e. event IDs to use as the prev events of the the next
generated event).

=cut

sub insert_outlier_event
{
   my $self = shift;
   my ( $event ) = @_;

   croak "Event not ref" unless ref $event;

   if( defined $event->{state_key} ) {
      $self->{current_state}{ join "\0", $event->{type}, $event->{state_key} }
         = $event;
   }
}

=head2 current_state_events

   @events = $room->current_state_events

Returns a list of events, in no particular order, that comprises the complete
current state; that is, the latest value of any event with a C<state_key>
field.

=cut

sub current_state_events
{
   my $self = shift;
   return values %{ $self->{current_state} };
}

=head2 get_current_state_event

   $event = $room->get_current_state_event( $type, $state_key )

Returns the latest state event for the given C<$type> and optional
C<$state_key>, or C<undef> if there is none.

=cut

sub get_current_state_event
{
   my $self = shift;
   my ( $type, $state_key ) = @_;
   $state_key //= "";

   return $self->{current_state}{ join "\0", $type, $state_key };
}

=head2 make_join_protoevent

   $protoevent = $room->make_join_protoevent( user_id => $user_id )

Returns a HASH reference containing most of the fields required to form the
protoevent response to a C</make_join> federation request to this room, if the
given C<$user_id> wishes to join it. The caller will have to supply the
C<origin> and C<origin_server_ts> fields before sending it back to the
requesting client. As a new HASH reference is returned by each call, the
caller is free to modify it inplace as required.

=cut

sub make_join_protoevent
{
   my $self = shift;
   my %args = @_;

   my $user_id = $args{user_id};

   my @auth_events = grep { defined } (
      $self->get_current_state_event( "m.room.create" ),
      $self->get_current_state_event( "m.room.join_rules" ),
   );

   return {
      type => "m.room.member",

      auth_events      => $self->make_event_refs( @auth_events ),
      content          => { membership => "join" },
      depth            => JSON::number($self->next_depth),
      prev_events      => $self->make_event_refs( @{ $self->{prev_events} } ),
      room_id          => $self->room_id,
      sender           => $user_id,
      state_key        => $user_id,
   };
}

=head2 id_for_event

    $event_id = $room->id_for_event( $event );

Gets a the event_id for the given event. For room version 1 and 2, the event_id
is pulled out of the event structure. For other room versions, it is calculated
from the hash of the event.

Fetches or calculates the event_id for the given event

=cut

sub id_for_event
{
   my $self = shift;
   my ( $event ) = @_;

   return SyTest::Federation::Protocol::id_for_event(
      $event, $self->room_version,
   );
}

1;
