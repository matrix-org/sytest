package SyTest::Federation::AuthChecks;

use strict;
use warnings;

use List::Util qw( first );

# A mixin containing the actual event authentication check logic

sub _find_auth_event_by_type
{
   my ( $accepted_events, $auth_events, $type ) = @_;

   return first { $_ and $_->{type} eq $type }
          map { $accepted_events->{$_} }
          map { $_->[0] } @$auth_events;
}

sub auth_check_event
{
   my $self = shift;
   my ( $event, $accepted_events ) = @_;

   # No event can be accepted if any of its own auth_events remains unaccepted
   $accepted_events->{$_} or return 0
      for map { $_->[0] } @{ $event->{auth_events} };

   my $type = $event->{type};

   # A couple of types of event are special
   if( $type eq "m.room.create" ) {
      return $self->auth_check_event_m_room_create( $event );
   }
   elsif( $type eq "m.room.member" ) {
      return $self->auth_check_event_m_room_member( $event, $accepted_events );
   }

   # Generic fallthrough which checks m.room.power_levels

   my $power_levels_event = _find_auth_event_by_type(
      $accepted_events, $event->{auth_events}, "m.room.power_levels"
   );

   # If no m.room.power_levels event exists (e.g. because of bootstrapping)
   # synthesize a default one
   my $content = $power_levels_event ? $power_levels_event->{content} : do {
      my $create_event = _find_auth_event_by_type(
         $accepted_events, $event->{auth_events}, "m.room.create"
      );

      my $room_creator = _creator_for_create_event( $create_event );
      return 0 unless defined $room_creator;

      {
         users => {
            $room_creator => 100,
         },
         users_default => 0,

         events => {
            "m.room.avatar"             => 50,
            "m.room.canonical_alias"    => 50,
            "m.room.history_visibility" => 100,
            "m.room.name"               => 50,
            "m.room.power_levels"       => 100,
         },
         events_default => 0,
         state_default  => 50,

         ban    => 50,
         invite => 0,
         kick   => 50,
         redact => 50,
      }
   };

   my $requires_level = $content->{events}{"m.room.power_levels"};
   $requires_level //= $content->{
      defined $event->{state_key} ? "state_default" : "event_default"
   };

   my $user_level = $content->{users}{ $event->{sender} };
   $user_level //= $content->{users_default};

   return 0 if $user_level < $requires_level;

   # TODO: Check special other rules for type

   return 1;
}

=head2 _creator_for_create_event

   my $creator = _creator_for_create_event( $create_event )

Returns the creator MXID for a given C<m.room.create> event. For room
version 11+, the creator is taken from the C<sender> field; for older
versions it is taken from C<content.creator>.

=cut

sub _creator_for_create_event
{
   my ( $create_event ) = @_;

   $create_event or
      return undef;

   my $room_version = $create_event->{content}{room_version};

   # For room version 11+ (or unstable/non-numeric versions), 'creator' is absent
   # from content; use sender instead.
   if( defined $room_version && ( $room_version !~ /\A[0-9]+\z/ || $room_version >= 11 ) ) {
      return $create_event->{sender};
   }

   # For older room versions, 'creator' must be present explicitly.
   return $create_event->{content}{creator};
}

sub auth_check_event_m_room_create
{
   my $self = shift;
   my ( $event ) = @_;

   # m.room.create really should not have any auth_events of its own
   @{ $event->{auth_events} } == 0 or
      return 0;

   # Any m.room.create event is acceptable, provided that the creator matches
   my $creator = _creator_for_create_event( $event );
   return defined( $creator ) and $event->{sender} eq $creator;
}

sub auth_check_event_m_room_member
{
   my $self = shift;
   my ( $event, $accepted_events ) = @_;

   $event->{content}{membership} eq "join" or
      die "TODO: This check can only test join events";

   # Users may only join themselves
   $event->{state_key} eq $event->{sender} or
      return 0;

   # For post-create bootstrapping, the room creator is always allowed to join
   # TODO(paul): Is this right?
   my $create_event = _find_auth_event_by_type(
      $accepted_events, $event->{auth_events}, "m.room.create"
   );

   my $creator = _creator_for_create_event( $create_event );
   if( $creator and $event->{state_key} eq $creator ) {
      return 1;
   }

   die "TODO: non-creator join";
}

1;
