use List::UtilsBy qw( partition_by );

prepare "Creating a room",
   requires => [qw( user can_create_room )],

   provides => [qw( room_id room_alias )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/createRoom",

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

         $event->{user_id} eq $user->user_id or
            die "Expected user_id to be ${\$user->user_id}";

         require_json_keys( my $content = $event->{content}, qw( creator ));
         $content->{creator} eq $user->user_id or
            die "Expected creator to be ${\$user->user_id}";

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

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "join" or
            die "Expected my membership as 'join'";

         return 1;
      });
   };

my $topic = "Testing topic for the new room";

test "Setting room topic reports m.room.topic to myself",
   requires => [qw( user await_event_for room_id user
                    can_set_room_topic )],

   do => sub {
      my ( $user, undef, $room_id, undef ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/state/m.room.topic",

         content => { topic => $topic },
      );
   },

   await => sub {
      my ( undef, $await_event_for, $room_id, $user ) = @_;

      $await_event_for->( $user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.topic";
         require_json_keys( $event, qw( room_id user_id content ));
         return unless $event->{room_id} eq $room_id;

         $event->{user_id} eq $user->user_id or
            die "Expected user_id to be ${\$user->user_id}";

         require_json_keys( my $content = $event->{content}, qw( topic ));
         $content->{topic} eq $topic or
            die "Expected topic to be '$topic'";

         return 1;
      });
   };

multi_test "Global initialSync",
   requires => [qw( user room_id
                    can_initial_sync can_set_room_topic )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         my $room;

         require_json_list( $body->{rooms} );
         foreach ( @{ $body->{rooms} } ) {
            require_json_keys( $_, qw( room_id membership state messages ));

            next unless $_->{room_id} eq $room_id;
            $room = $_;
            last;
         }

         ok( $room, "my membership in the room is reported" );

         is_eq( $room->{membership}, "join", "room membership is 'join'" );
         is_eq( $room->{visibility}, "public", "room visibility is 'public'" );

         my %state_by_type = partition_by { $_->{type} } @{ $room->{state} };

         $state_by_type{"m.room.topic"} or
            die "Expected m.room.topic state";
         require_json_keys( my $topic_state = $state_by_type{"m.room.topic"}[0], qw( content ));
         require_json_keys( $topic_state->{content}, qw( topic ));
         is_eq( $topic_state->{content}{topic}, $topic, "m.room.topic content topic" );

         $state_by_type{"m.room.power_levels"} or
            die "Expected m.room.power_levels";
         require_json_keys( my $power_level_state = $state_by_type{"m.room.power_levels"}[0], qw( content ));
         require_json_keys( my $levels = $power_level_state->{content}, qw( users ));
         my $user_levels = $levels->{users};
         ok( exists $user_levels->{ $user->user_id },
            "user level exists for room creator" );
         ok( $user_levels->{ $user->user_id } > 0,
            "room creator has nonzero power level" );

         my $messages = $room->{messages};
         require_json_keys( $messages, qw( start end chunk ));
         require_json_list( my $chunk = $messages->{chunk} );

         ok( scalar @$chunk, "room messages chunk reports some messages" );

         Future->done(1);
      });
   };

test "Global initialSync with limit=0 gives no messages",
   requires => [qw( user room_id can_initial_sync )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/initialSync",
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
   requires => [qw( user room_id can_room_initial_sync )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( state messages presence ));

         my %state_by_type = partition_by { $_->{type} } @{ $body->{state} };

         ok( $state_by_type{$_}, "room has state $_" ) for
            qw( m.room.create m.room.join_rules m.room.member );

         is_eq( $state_by_type{"m.room.join_rules"}[0]{content}{join_rule}, "public",
            "join rule is public" );

         is_eq( $state_by_type{"m.room.topic"}[0]{content}{topic}, $topic,
            "m.room.topic content topic" );

         my %members = map { $_->{user_id} => $_ } @{ $state_by_type{"m.room.member"} };

         ok( $members{ $user->user_id }, "room members has my own membership" );
         is_eq( $members{ $user->user_id }->{content}{membership}, "join",
            "my own room membership is 'join'" );

         my %presence = map { $_->{content}{user_id} => $_ } @{ $body->{presence} };

         ok( $presence{ $user->user_id }, "found my own presence" );

         require_json_keys( $presence{ $user->user_id }, qw( type content ));
         require_json_keys( my $content = $presence{ $user->user_id }{content},
            qw( presence status_msg last_active_ago ));

         is_eq( $content->{presence}, "online", "my presence is 'online'" );

         my $chunk = $body->{messages}{chunk};

         ok( scalar @$chunk, "room messages chunk reports some messages" );

         Future->done(1);
      });
   };

test "Room initialSync with limit=0 gives no messages",
   requires => [qw( user room_id can_initial_sync )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/initialSync",
         params => { limit => 0 },
      )->then( sub {
         my ( $body ) = @_;

         my $chunk = $body->{messages}{chunk};
         scalar @$chunk == 0 or
            die "Expected not to find any messages";

         Future->done(1);
      });
   };
