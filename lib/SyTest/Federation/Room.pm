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

      prev_events => [],
   }, $class;

   my $create_event = $self->create_event(
      type => "m.room.create",

      auth_events => [],
      content     => { creator => $creator },
      depth       => 0,
      room_id     => $room_id,
      sender      => $creator,
      state_key   => "",
   );

   my $joinrules_event = $self->create_event(
      type => "m.room.join_rules",

      auth_events => make_event_refs( $create_event ),
      content     => { join_rule => "public" },
      depth       => 0,
      room_id     => $room_id,
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

   my $event = $server->create_event(
      %fields,

      prev_events => $self->{prev_events},
      prev_state  => [], # TODO
   );

   $self->{prev_events} = make_event_refs( $event );

   return $event;
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
      prev_events      => [],
      room_id          => $self->room_id,
      sender           => $user_id,
      state_key        => $user_id,
   };
}

1;
