use Future::Utils qw( repeat );

my $senduser_fixture = local_user_fixture();

my $local_user_fixture = local_user_fixture();

my $remote_fixture = remote_user_fixture();

my $room_fixture = magic_room_fixture(
   requires_users => [ $senduser_fixture, $local_user_fixture, $remote_fixture ],
);

my $msgtype = "m.message";
my $msgbody = "Room message for 33room-messages";

test "Local room members see posted message events",
   requires => [ $senduser_fixture, $local_user_fixture, $room_fixture,
                 qw( can_send_message )],

   proves => [qw( can_receive_room_message_locally )],

   do => sub {
      my ( $senduser, $local_user, $room_id ) = @_;

      Future->needs_all(
         matrix_sync( $senduser ),
         matrix_sync( $local_user ),
      )->then( sub {
         matrix_send_room_message( $senduser, $room_id,
            content => { msgtype => $msgtype, body => $msgbody },
         )
      })->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_sync_timeline_contains( $recvuser, $room_id, check => sub {
               my ( $event ) = @_;

               log_if_fail "Event for ${\$recvuser->user_id}", $event;

               return unless $event->{type} eq "m.room.message";

               assert_json_keys( $event, qw( type content sender ));
               assert_json_keys( my $content = $event->{content}, qw( msgtype body ));

               $content->{msgtype} eq $msgtype or
                  die "Expected msgtype as $msgtype";
               $content->{body} eq $msgbody or
                  die "Expected body as '$msgbody'";
               $event->{sender} eq $senduser->user_id or
                  die "Expected sender user_id as ${\$senduser->sender}\n";

               return 1;
            });
         } $senduser, $local_user )
      });
   };

test "Fetching eventstream a second time doesn't yield the message again",
   requires => [ $senduser_fixture, $local_user_fixture,
                 qw( can_receive_room_message_locally )],

   check => sub {
      my ( $senduser, $local_user ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         matrix_get_events( $recvuser,
            from    => $recvuser->eventstream_token,
            timeout => 0,
         )->then( sub {
            my ( $body ) = @_;

            foreach my $event ( @{ $body->{chunk} } ) {
               next unless $event->{type} eq "m.room.message";
               my $content = $event->{content};

               $content->{body} eq $msgbody and
                  die "Expected not to recieve duplicate message\n";
            }

            Future->done;
         })
      } $senduser, $local_user )->then_done(1);
   };

test "Local non-members don't see posted message events",
   requires => [ local_user_fixture(), $room_fixture, ],

   do => sub {
      my ( $nonmember, $room_id ) = @_;

      Future->wait_any(
         await_sync_timeline_contains( $nonmember, $room_id, check => sub {
            my ( $event ) = @_;
            log_if_fail "Received event:", $event;

            return unless $event->{type} eq "m.room.message";

            assert_json_keys( $event, qw( type content user_id ));

            die "Nonmember received event about a room they're not a member of";
         }),

         # So as not to wait too long, give it 500msec to not arrive
         delay( 0.5 )->then_done(1),
      );
   };

test "Local room members can get room messages",
   requires => [ $senduser_fixture, $local_user_fixture, $room_fixture,
                 qw( can_send_message can_get_messages )],

   check => sub {
      my ( $senduser, $local_user, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         matrix_get_room_messages( $user, $room_id, limit => 1 )->then( sub {
            my ( $body ) = @_;
            log_if_fail "Body:", $body;

            assert_json_keys( $body, qw( start end chunk ));
            assert_json_list( my $chunk = $body->{chunk} );

            scalar @$chunk == 1 or
               die "Expected one message";

            my ( $event ) = @$chunk;

            assert_json_keys( $event, qw( type room_id user_id content ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";

            Future->done(1);
         });
      } $senduser, $local_user )
   };

test "Remote room members also see posted message events",
   requires => [ $senduser_fixture, $remote_fixture, $room_fixture,
                qw( can_receive_room_message_locally )],

   # this test frequently times out for unknown reasons
   bug => "synapse#1679",

   do => sub {
      my ( $senduser, $remote_user, $room_id ) = @_;

      await_sync_timeline_contains( $remote_user, $room_id, check => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.message";

         assert_json_keys( $event, qw( type content sender ));
         assert_json_keys( my $content = $event->{content}, qw( msgtype body ));

         $content->{msgtype} eq $msgtype or
            die "Expected msgtype as $msgtype";
         $content->{body} eq $msgbody or
            die "Expected body as '$msgbody'";
         $event->{sender} eq $senduser->user_id or
            die "Expected sender user_id as ${\$senduser->user_id}\n";

         return 1;
      });
   };

test "Remote room members can get room messages",
   requires => [ $remote_fixture, $room_fixture,
                 qw( can_send_message can_get_messages )],

   check => sub {
      my ( $remote_user, $room_id ) = @_;

      matrix_get_room_messages( $remote_user, $room_id, limit => 1 )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( start end chunk ));
         assert_json_list( my $chunk = $body->{chunk} );

         scalar @$chunk == 1 or
            die "Expected one message";

         my ( $event ) = @$chunk;

         assert_json_keys( $event, qw( type room_id user_id content ));

         $event->{room_id} eq $room_id or
            die "Expected room_id to be $room_id";

         Future->done(1);
      });
   };

test "Message history can be paginated",
   requires => [ magic_local_user_and_room_fixtures() ],

   proves => [qw( can_paginate_room )],

   do => sub {
      my ( $user, $room_id ) = @_;

      ( repeat {
         matrix_send_room_text_message( $user, $room_id,
            body => "Message number $_[0]"
         )
      } foreach => [ 1 .. 20 ] )->then( sub {
         matrix_get_room_messages( $user, $room_id, limit => 5 )
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "First messages body", $body;

         my $chunk = $body->{chunk};
         @$chunk == 5 or
            die "Expected 5 messages";

         # This should be 20 to 16
         assert_eq( $chunk->[0]{content}{body}, "Message number 20",
            'chunk[0] content body' );
         assert_eq( $chunk->[4]{content}{body}, "Message number 16",
            'chunk[4] content body' );

         matrix_get_room_messages( $user, $room_id, limit => 5, from => $body->{end} )
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Second message body", $body;

         my $chunk = $body->{chunk};
         @$chunk == 5 or
            die "Expected 5 messages";

         # This should be 15 to 11
         assert_eq( $chunk->[0]{content}{body}, "Message number 15",
            'chunk[0] content body' );
         assert_eq( $chunk->[4]{content}{body}, "Message number 11",
            'chunk[4] content body' );

         Future->done(1);
      });
   };

test "Message history can be paginated over federation",
   requires => do {
      my $local_user_fixture = local_user_fixture();

      [ $local_user_fixture,
        magic_room_fixture( requires_users => [ $local_user_fixture ], with_alias => 1 ),
        remote_user_fixture(),

        qw( can_paginate_room ),
     ];
   },

   proves => [qw( can_paginate_room_remotely )],

   do => sub {
      my ( $creator, $room_id, $room_alias, $remote_user ) = @_;

      ( repeat {
         matrix_send_room_text_message( $creator, $room_id,
            body => "Message number $_[0]"
         )
      } foreach => [ 1 .. 20 ] )->then( sub {
         matrix_join_room( $remote_user, $room_alias );
      })->then( sub {
         matrix_sync( $remote_user )
      })->then( sub {
         # The member event is likely to arrive first
         matrix_get_room_messages( $remote_user, $room_id, limit => 5+1 )
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "First messages body", $body;

         my $chunk = $body->{chunk};
         @$chunk == 6 or
            die "Expected 6 messages";

         assert_eq( $chunk->[0]{type}, "m.room.member",
            'first message type' );
         assert_eq( $chunk->[0]{state_key}, $remote_user->user_id,
            'first message state_key' );

         shift @$chunk;

         # This should be 20 to 16
         assert_eq( $chunk->[0]{content}{body}, "Message number 20",
            'chunk[0] content body' );
         assert_eq( $chunk->[4]{content}{body}, "Message number 16",
            'chunk[4] content body' );

         matrix_get_room_messages( $remote_user, $room_id, limit => 5, from => $body->{end} )
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Second message body", $body;

         my $chunk = $body->{chunk};
         @$chunk == 5 or
            die "Expected 5 messages";

         # This should be 15 to 11
         assert_eq( $chunk->[0]{content}{body}, "Message number 15",
            'chunk[0] content body' );
         assert_eq( $chunk->[4]{content}{body}, "Message number 11",
            'chunk[4] content body' );

         matrix_send_room_text_message( $creator, $room_id,
            body => "Marker message"
         )
      })->then( sub {
         my ( $event_id ) = @_;

         # Wait for the message we just sent, ensuring that we don't see any
         # of the backfilled events.
         await_sync_timeline_contains( $remote_user, $room_id, check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";

            log_if_fail "Received event", $event;

            assert_eq( $event->{event_id}, $event_id, "Got unexpected event");

            return 1;
         })
      });
   };
