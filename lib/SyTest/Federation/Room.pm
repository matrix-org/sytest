package SyTest::Federation::Room;

use strict;
use warnings;

use Carp;

use List::Util qw( max );
use List::UtilsBy qw( extract_by );

=head1 NAME

C<SyTest::Federation::Room> - represent a single Room instance

=cut

sub make_event_refs
{
   [ map { [ $_->{event_id}, $_->{hashes} ] } @_ ];
}

=head1 CONSTRUCTOR

=cut

=head2 new

   $room = SyTest::Federation::Room->new( room_id => $room_id, datastore => $store )

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

   return bless {
      room_id   => $room_id,
      datastore => $datastore,

      current_state => {},
      prev_events => [],
   }, $class;
}

=head1 METHODS

=cut

=head2 room_id

   $room_id = $room->room_id

Accessor to return the room ID.

=cut

sub room_id
{
   return $_[0]->{room_id};
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

   my $room_version = $args{room_version};

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

   $event = $room->create_event( %fields )

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

   $fields{prev_state} = [] if defined $fields{state_key}; # TODO: give it a better value

   my @auth_events = grep { defined } (
      $self->get_current_state_event( "m.room.create" ),
      $self->get_current_state_event( "m.room.join_rules" ),
      $self->get_current_state_event( "m.room.power_levels" ),
      $self->get_current_state_event( "m.room.member", $fields{sender} ),
   );
   $fields{auth_events} //= make_event_refs( @auth_events ),

   $fields{depth} //= JSON::number($self->next_depth);

   $fields{prev_events} //= make_event_refs( @{ $self->{prev_events} } );

   return $self->{datastore}->create_event(
      room_id => $self->room_id,
      %fields,
   );
}

=head2 create_and_insert_event

   $event = $room->create_and_insert_event( %fields )

Constructs a new event via C<create_event>, updates the current state, if it is a
state event, and records the event as the room's next prev_event.

=cut

sub create_and_insert_event
{
   my $self = shift;
   my %fields = @_;

   my $event = $self->create_event( %fields );

   $self->_insert_event( $event );

   $self->{prev_events} = [ $event ];

   return $event;
}

sub insert_event
{
   my $self = shift;
   my ( $event ) = @_;

   $self->_insert_event( $event );

   my $prev_events = $self->{prev_events};
   push @$prev_events, $event;

   # Remove from $self->{prev_events} any event IDs that are now recursively
   # implied by this new event.
   my %to_remove = map { $_->[0] => 1 } @{ $event->{prev_events} };
   extract_by { $to_remove{ $_->{event_id} } } @$prev_events;
}

sub _insert_event
{
   my $self = shift;
   my ( $event ) = @_;

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

      auth_events      => make_event_refs( @auth_events ),
      content          => { membership => "join" },
      depth            => JSON::number($self->next_depth),
      prev_events      => make_event_refs( @{ $self->{prev_events} } ),
      room_id          => $self->room_id,
      sender           => $user_id,
      state_key        => $user_id,
   };
}

1;
