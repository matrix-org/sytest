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

multi_test "Global initialSync",
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
            require_json_keys( $room, qw( room_id membership messages ));

            next unless $room->{room_id} eq $room_id;
            $found = $room;
            last;
         }

         ok( $found, "my membership in the room is reported" );

         ok( $found->{membership} eq "join", "room membership is 'join'" );
         ok( $found->{visibility} eq "public", "room visibility is 'public'" );

         my $messages = $found->{messages};
         require_json_keys( $messages, qw( start end chunk ));
         require_json_list( my $chunk = $messages->{chunk} );

         ok( scalar @$chunk, "room messages chunk reports some messages" );

         Future->done(1);
      });
   };

test "Global initialSync with limit=0 gives no messages",
   requires => [qw( do_request_json room_id can_initial_sync )],

   check => sub {
      my ( $do_request_json, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/initialSync",
         params => { limit => 0 },
      )->then( sub {
         my ( $body ) = @_;

         my $found;
         foreach my $room ( @{ $body->{rooms} } ) {
            $found = $room, last if $room->{room_id} eq $room_id;
         }

         $found or die "Failed to find room";

         my $chunk = $found->{messages}{chunk};
         scalar @$chunk == 0 or
            die "Expected not to find any messages";

         Future->done(1);
      });
   };

multi_test "Room initialSync",
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

         ok( $state_by_type{$_}, "room has state $_" ) for
            qw( m.room.create m.room.member );

         my %members;
         $members{$_->{user_id}} = $_ for @{ $state_by_type{"m.room.member"} };

         ok( $members{$user->user_id}, "room members has my own membership" );
         ok( $members{$user->user_id}->{membership} eq "join", "my own room membership is 'join'" );

         my %presence;
         $presence{$_->{content}{user_id}} = $_ for @{ $body->{presence} };

         ok( $presence{$user->user_id}, "found my own presence" );

         require_json_keys( $presence{$user->user_id}, qw( type content ));
         require_json_keys( my $content = $presence{$user->user_id}{content},
            qw( presence status_msg last_active_ago ));

         ok( $content->{presence} eq "online", "my presence is 'online'" );

         my $chunk = $body->{messages}{chunk};

         ok( scalar @$chunk, "room messages chunk reports some messages" );

         Future->done(1);
      });
   };

test "Room initialSync with limit=0 gives no messages",
   requires => [qw( do_request_json room_id can_initial_sync )],

   check => sub {
      my ( $do_request_json, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/rooms/$room_id/initialSync",
         params => { limit => 0 },
      )->then( sub {
         my ( $body ) = @_;

         my $chunk = $body->{messages}{chunk};
         scalar @$chunk == 0 or
            die "Expected not to find any messages";

         Future->done(1);
      });
   };
