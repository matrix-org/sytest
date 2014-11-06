prepare "Creating a room",
   requires => [qw( do_request_json can_create_room )],

   do => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "POST",
         uri    => "/createRoom",

         content => {
            visibility      => "public",
            room_alias_name => "30room-state",
         },
      )->then( sub {
         my ( $body ) = @_;

         provide room_id    => $body->{room_id};
         provide room_alias => $body->{room_alias};

         Future->done(1);
      });
   };

test "Room creation reports m.room.create to myself",
   requires => [qw( await_event_for room_id user )],

   await => sub {
      my ( $await_event_for, $room_id, $user ) = @_;

      $await_event_for->( $user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.create";
         json_keys_ok( $event, qw( room_id user_id content ));
         return unless $event->{room_id} eq $room_id;

         $event->{user_id} eq $user->user_id or die "Expected user_id to be ${\$user->user_id}";

         json_keys_ok( my $content = $event->{content}, qw( creator ));
         $content->{creator} eq $user->user_id or die "Expected creator to be ${\$user->user_id}";

         return 1;
      });
   };

test "Room creation reports m.room.member to myself",
   requires => [qw( await_event_for room_id user )],

   await => sub {
      my ( $await_event_for, $room_id, $user ) = @_;

      $await_event_for->( $user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";
         json_keys_ok( $event, qw( room_id user_id state_key content ));
         return unless $event->{room_id} eq $room_id;
         return unless $event->{state_key} eq $user->user_id;

         $event->{membership} eq "join" or
            die "Expected my membership as 'join'";

         return 1;
      });
   };

test "initialSync sees my membership in the room",
   requires => [qw( do_request_json room_id can_initial_sync )],

   check => sub {
      my ( $do_request_json, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         my $found;

         json_list_ok( $body->{rooms} );
         foreach my $room ( @{ $body->{rooms} } ) {
            json_keys_ok( $room, qw( room_id membership ));

            next unless $room->{room_id} eq $room_id;
            $found++;

            $room->{membership} eq "join" or die "Expected room membership to be 'join'\n";
            $room->{visibility} eq "public" or die "Expected room visibility to be 'public'\n";
         }

         $found or
            die "Failed to find our newly-created room";

         Future->done(1);
      });
   };
