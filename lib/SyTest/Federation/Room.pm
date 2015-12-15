package SyTest::Federation::Room;

use strict;
use warnings;

use Carp;

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

   $room = SyTest::Federation::Room->new( room_id => $room_id )

Constructs a new Room instance, initially blank containing no state or events.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $room_id = $args{room_id} or
      croak "Require a 'room_id'";

   return bless {
      room_id => $room_id,

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

=head2 create_initial_events

   $room->create_initial_events( server => $server, creator => $creator )

Convenience helper method to create all the initial state events required at
room creation time. It supplies the C<m.room.create> event with the given
C<$creator> user ID as the room's creator, the C<m.room.member> event for this
user, and a C<m.room.join_rules> to set the room join permission as C<public>.

C<$server> is an instance of L<SyTest::Federation::Server> required to
actually create and persist the individual events.

=cut

sub create_initial_events
{
   my $self = shift;
   my %args = @_;

   my $server = $args{server} or
      croak "Require a 'server'";

   my $creator = $args{creator} or
      croak "Require a 'creator'";

   # TODO(paul): have create_event calculate the depth field. But currently
   #   synapse doesn't check it (SYN-507)

   $self->create_event(
      server => $server,
      type   => "m.room.create",

      content     => { creator => $creator },
      depth       => 0,
      sender      => $creator,
      state_key   => "",
   );

   $self->create_event(
      server => $server,
      type   => "m.room.member",

      content     => { membership => "join" },
      depth       => 0,
      sender      => $creator,
      state_key   => $creator,
   );

   $self->create_event(
      server => $server,
      type   => "m.room.join_rules",

      content     => { join_rule => "public" },
      depth       => 0,
      sender      => $creator,
      state_key   => "",
   );
}

=head2 create_event

   $event = $room->create_event( server => $server, %fields )

Constructs a new event in the room and updates the current state, if it is a
state event. This helper also fills in the C<prev_events> and C<auth_events>
lists, meaning the caller does not have to.

C<$server> is an instance of L<SyTest::Federation::Server> required to
actually create and persist the event.

=cut

sub create_event
{
   my $self = shift;
   my %fields = @_;

   my $server = delete $fields{server} or
      croak "Require a 'server'";

   $fields{prev_state} = [] if defined $fields{state_key}; # TODO: give it a better value

   my @auth_events = grep { defined } (
      $self->get_current_state_event( "m.room.create" ),
      $self->get_current_state_event( "m.room.member", $fields{sender} ),
   );

   my $event = $server->create_event(
      %fields,

      auth_events => make_event_refs( @auth_events ),
      room_id     => $self->room_id,
      prev_events => $self->{prev_events},
   );

   $self->{prev_events} = make_event_refs( $event );

   if( defined $fields{state_key} ) {
      $self->{current_state}{ join "\0", $fields{type}, $fields{state_key} }
         = $event;
   }

   return $event;
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
      # TODO(paul): depth should be calculated as 1 + max(depth of auth_events)
      #   but for now, synapse doesn't test it (SYN-507)
      depth            => 0,
      prev_events      => $self->{prev_events},
      room_id          => $self->room_id,
      sender           => $user_id,
      state_key        => $user_id,
   };
}

1;
