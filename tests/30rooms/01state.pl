use List::UtilsBy qw( partition_by );

my $user_fixture = local_user_fixture(
   presence => "online",
);

my $room_fixture = fixture(
   requires => [ $user_fixture ],

   setup => sub {
      my ( $user ) = @_;

      matrix_create_room( $user,
         visibility => "public",
      );
   },
);

test "Room creation reports m.room.create to myself",
   requires => [ $user_fixture, $room_fixture ],

   do => sub {
      my ( $user, $room_id ) = @_;

      await_event_for( $user, filter => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.create";
         assert_json_keys( $event, qw( room_id user_id content ));
         return unless $event->{room_id} eq $room_id;

         $event->{user_id} eq $user->user_id or
            die "Expected user_id to be ${\$user->user_id}";

         assert_json_keys( my $content = $event->{content}, qw( creator ));
         $content->{creator} eq $user->user_id or
            die "Expected creator to be ${\$user->user_id}";

         return 1;
      });
   };

test "Room creation reports m.room.member to myself",
   requires => [ $user_fixture, $room_fixture ],

   do => sub {
      my ( $user, $room_id ) = @_;

      await_event_for( $user, filter => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";
         assert_json_keys( $event, qw( room_id user_id state_key content ));
         return unless $event->{room_id} eq $room_id;
         return unless $event->{state_key} eq $user->user_id;

         assert_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "join" or
            die "Expected my membership as 'join'";

         return 1;
      });
   };

my $topic = "Testing topic for the new room";

test "Setting room topic reports m.room.topic to myself",
   requires => [ $user_fixture, $room_fixture,
                qw( can_set_room_topic )],

   do => sub {
      my ( $user, $room_id ) = @_;

      matrix_put_room_state( $user, $room_id,
         type    => "m.room.topic",
         content => { topic => $topic },
      )->then( sub {
         await_event_for( $user, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.topic";
            assert_json_keys( $event, qw( room_id user_id content ));
            return unless $event->{room_id} eq $room_id;

            $event->{user_id} eq $user->user_id or
               die "Expected user_id to be ${\$user->user_id}";

            assert_json_keys( my $content = $event->{content}, qw( topic ));
            $content->{topic} eq $topic or
               die "Expected topic to be '$topic'";

            return 1;
         });
      });
   };

test "Global initialSync",
   requires => [ $user_fixture, $room_fixture,
                qw( can_initial_sync can_set_room_topic )],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_initialsync( $user )->then( sub {
         my ( $body ) = @_;

         my $room;

         assert_json_list( $body->{rooms} );
         foreach ( @{ $body->{rooms} } ) {
            assert_json_keys( $_, qw( room_id membership state messages ));

            next unless $_->{room_id} eq $room_id;
            $room = $_;
            last;
         }

         assert_ok( $room, "my membership in the room is reported" );

         assert_eq( $room->{membership}, "join", "room membership is 'join'" );
         assert_eq( $room->{visibility}, "public", "room visibility is 'public'" );

         my %state_by_type = partition_by { $_->{type} } @{ $room->{state} };

         $state_by_type{"m.room.topic"} or
            die "Expected m.room.topic state";
         assert_json_keys( my $topic_state = $state_by_type{"m.room.topic"}[0], qw( content ));
         assert_json_keys( $topic_state->{content}, qw( topic ));
         assert_eq( $topic_state->{content}{topic}, $topic, "m.room.topic content topic" );

         $state_by_type{"m.room.power_levels"} or
            die "Expected m.room.power_levels";
         assert_json_keys( my $power_level_state = $state_by_type{"m.room.power_levels"}[0], qw( content ));
         assert_json_keys( my $levels = $power_level_state->{content}, qw( users ));
         my $user_levels = $levels->{users};
         assert_ok( exists $user_levels->{ $user->user_id },
            "user level exists for room creator" );
         assert_ok( $user_levels->{ $user->user_id } > 0,
            "room creator has nonzero power level" );

         my $messages = $room->{messages};
         assert_json_keys( $messages, qw( start end chunk ));
         assert_json_list( my $chunk = $messages->{chunk} );

         assert_ok( scalar @$chunk, "room messages chunk reports some messages" );

         Future->done(1);
      });
   };

test "Global initialSync with limit=0 gives no messages",
   requires => [ $user_fixture, $room_fixture,
                qw( can_initial_sync )],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_initialsync( $user, limit => 0 )->then( sub {
         my ( $body ) = @_;

         my $found;
         foreach my $room ( @{ $body->{rooms} } ) {
            $found = $room, last if $room->{room_id} eq $room_id;
         }

         $found or die "Failed to find room";

         assert_json_empty_list( $found->{messages}{chunk} );

         Future->done(1);
      });
   };

test "Room initialSync",
   requires => [ $user_fixture, $room_fixture,
                qw( can_room_initial_sync )],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_initialsync_room( $user, $room_id )
      ->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( state messages presence ));

         my %state_by_type = partition_by { $_->{type} } @{ $body->{state} };

         assert_ok( $state_by_type{$_}, "room has state $_" ) for
            qw( m.room.create m.room.join_rules m.room.member );

         assert_eq( $state_by_type{"m.room.join_rules"}[0]{content}{join_rule}, "public",
            "join rule is public" );

         assert_eq( $state_by_type{"m.room.topic"}[0]{content}{topic}, $topic,
            "m.room.topic content topic" );

         my %members = map { $_->{user_id} => $_ } @{ $state_by_type{"m.room.member"} };

         assert_ok( $members{ $user->user_id }, "room members has my own membership" );
         assert_eq( $members{ $user->user_id }->{content}{membership}, "join",
            "my own room membership is 'join'" );

         my %presence = map { $_->{content}{user_id} => $_ } @{ $body->{presence} };

         assert_ok( $presence{ $user->user_id }, "found my own presence" );

         assert_json_keys( $presence{ $user->user_id }, qw( type content ));
         assert_json_keys( my $content = $presence{ $user->user_id }{content},
            qw( presence status_msg last_active_ago ));

         assert_eq( $content->{presence}, "online", "my presence is 'online'" );

         my $chunk = $body->{messages}{chunk};

         assert_ok( scalar @$chunk, "room messages chunk reports some messages" );

         Future->done(1);
      });
   };

test "Room initialSync with limit=0 gives no messages",
   requires => [ $user_fixture, $room_fixture,
                qw( can_initial_sync )],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_initialsync_room( $user, $room_id, limit => 0 )
      ->then( sub {
         my ( $body ) = @_;

         assert_json_empty_list( $body->{messages}{chunk} );

         Future->done(1);
      });
   };


sub set_test_state
{
   my ( $user, $room_id ) = @_;

   matrix_put_room_state( $user, $room_id,
         type      => "a.test.state.type",
         state_key => "",
         content   => { "a_key" => "a_value" },
   )->then( sub {
      matrix_initialsync_room( $user, $room_id, limit => 0 );
   })->then( sub {
      my ( $body ) = @_;

      my %state_by_type = partition_by { $_->{type} } @{ $body->{state} };

      my $event_id = $state_by_type{"a.test.state.type"}[0]{event_id};

      Future->done( $event_id );
   });
}


test "Setting state twice is idempotent",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      my ( $event_id_1, $event_id_2 );

      set_test_state( $user, $room_id )->then( sub {
         ( $event_id_1 ) = @_;

         set_test_state( $user, $room_id );
      })->then( sub {
         ( $event_id_2 ) = @_;

         $event_id_1 eq $event_id_2 or
            die "Did not expect a new event when uploading the same state a second time";

         Future->done(1);
      });
   };
