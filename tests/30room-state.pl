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
         require_json_keys( $event, qw( room_id user_id content ));
         return unless $event->{room_id} eq $room_id;

         $event->{user_id} eq $user->user_id or die "Expected user_id to be ${\$user->user_id}";

         require_json_keys( my $content = $event->{content}, qw( creator ));
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
         require_json_keys( $event, qw( room_id user_id state_key content ));
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

         require_json_list( $body->{rooms} );
         foreach my $room ( @{ $body->{rooms} } ) {
            require_json_keys( $room, qw( room_id membership ));

            next unless $room->{room_id} eq $room_id;
            $found++;

            $room->{membership} eq "join" or die "Expected room membership to be 'join'\n";
            $room->{visibility} eq "public" or die "Expected room visibility to be 'public'\n";
         }

         $found or
            die "Filed to find our newly-created room";

         Future->done(1);
      });
   };

test "Room initialSync sees room state",
   requires => [qw( do_request_json room_id user can_room_initial_sync )],

   check => sub {
      my ( $do_request_json, $room_id, $user ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         my %state_by_type;
         push @{ $state_by_type{$_->{type}} }, $_ for @{ $body->{state} };

         $state_by_type{$_} or die "Expected $_ events" for
            qw( m.room.create m.room.member );

         my %members;
         $members{$_->{user_id}} = $_ for @{ $state_by_type{"m.room.member"} };

         $members{$user->user_id} or die "Expected to find my own membership";
         $members{$user->user_id}->{membership} eq "join" or
            die "Expected my own membership to be 'join'\n";

         Future->done(1);
      });
   };

test "Room initialSync sees room member presence",
   requires => [qw( do_request_json room_id user can_room_initial_sync )],

   check => sub {
      my ( $do_request_json, $room_id, $user ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         my %presence;
         $presence{$_->{content}{user_id}} = $_ for @{ $body->{presence} };

         $presence{$user->user_id} or die "Expected to find my own presence";

         require_json_keys( $presence{$user->user_id}, qw( type content ));
         require_json_keys( my $content = $presence{$user->user_id}{content},
            qw( presence status_msg last_active_ago ));

         $content->{presence} eq "online" or
            die "Expected my own presence to be 'online'\n";

         Future->done(1);
      });
   };
