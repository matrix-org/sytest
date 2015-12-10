package SyTest::Federation::Room;

use strict;
use warnings;

sub make_event_refs
{
   [ map { [ $_->{event_id}, $_->{hashes} ] } @_ ];
}

sub create
{
   my $class = shift;
   my %args = @_;

   my $server = $args{server};

   my $creator = $args{creator};
   my $room_id = $args{room_id} // $server->next_room_id;

   my $self = bless {
      room_id => $room_id,
      server  => $server,

      current_state => {},
      prev_events => [],
   }, $class;

   my $create_event = $self->create_event(
      type => "m.room.create",

      auth_events => [],
      content     => { creator => $creator },
      depth       => 0,
      sender      => $creator,
      state_key   => "",
   );

   my $creator_member_event = $self->create_event(
      type => "m.room.member",

      auth_events => make_event_refs( $create_event ),
      content     => { membership => "join" },
      depth       => 0,
      sender      => $creator,
      state_key   => $creator,
   );

   my $joinrules_event = $self->create_event(
      type => "m.room.join_rules",

      auth_events => make_event_refs( $create_event, $creator_member_event ),
      content     => { join_rule => "public" },
      depth       => 0,
      sender      => $creator,
      state_key   => "",
   );

   # TODO: this will want to be better
   $self->{auth_events} = make_event_refs( $create_event, $joinrules_event );

   return $self;
}

sub room_id
{
   return $_[0]->{room_id};
}

sub create_event
{
   my $self = shift;
   my %fields = @_;

   my $server = $self->{server};

   $fields{prev_state} = [] if defined $fields{state_key}; # TODO: give it a better value

   my $event = $server->create_event(
      %fields,

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

sub current_state_events
{
   my $self = shift;
   return values %{ $self->{current_state} };
}

sub make_join_protoevent
{
   my $self = shift;
   my %args = @_;

   my $user_id = $args{user_id};

   my $server = $self->{server};

   return {
      type => "m.room.member",

      auth_events      => $self->{auth_events},
      content          => { membership => "join" },
      depth            => 0,
      event_id         => my $join_event_id = $server->next_event_id,
      origin           => $server->server_name,
      origin_server_ts => $server->time_ms,
      prev_events      => $self->{prev_events},
      room_id          => $self->room_id,
      sender           => $user_id,
      state_key        => $user_id,
   };
}

1;
