package SyTest::Federation::Room;

use strict;
use warnings;

sub make_auth_events
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

   my $create_event = $server->create_event(
      type => "m.room.create",

      auth_events => [],
      prev_events => [],
      prev_state  => [],
      content     => { creator => $creator },
      depth       => 0,
      room_id     => $room_id,
      sender      => $creator,
      state_key   => "",
   );

   my $joinrules_event = $server->create_event(
      type => "m.room.join_rules",

      auth_events => make_auth_events( $create_event ),
      prev_events => make_auth_events( $create_event ),
      prev_state  => [],
      content     => { join_rule => "public" },
      depth       => 0,
      room_id     => $room_id,
      sender      => $creator,
      state_key   => "",
   );

   return bless {
      room_id => $room_id,
      server  => $server,

      # TODO: this will want to be better
      auth_events => make_auth_events( $create_event, $joinrules_event ),
   }, $class;
}

sub room_id
{
   return $_[0]->{room_id};
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
