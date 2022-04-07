use List::Util qw( first );

sub inviteonly_room_fixture
{
   my %args = @_;

   fixture(
      requires => [ $args{creator} ],

      setup => sub {
         my ( $creator ) = @_;

         matrix_create_room( $creator,
            preset => "private_chat",
         )->then( sub {
            my ( $room_id ) = @_;

            await_sync_timeline_contains($creator, $room_id, check => sub {
               my ( $event ) = @_;
               return unless $event->{type} eq "m.room.join_rules";
               $event->{content}{join_rule} eq "invite" or
                  die "Expected join rule to be 'invite'";
               return 1;
            });
            Future->done( $room_id );
         });
      }
   )
}

push our @EXPORT, qw( inviteonly_room_fixture );

multi_test "Can invite users to invite-only rooms",
   # TODO: deprecated endpoint used in this test
   requires => do {
      my $creator_fixture = local_user_fixture();

      [
         $creator_fixture,
         local_user_fixture(),
         inviteonly_room_fixture( creator => $creator_fixture ),
         qw( can_invite_room ),
      ];
   },

   do => sub {
      my ( $creator, $invitee, $room_id ) = @_;

      matrix_invite_user_to_room( $creator, $invitee, $room_id )
         ->SyTest::pass_on_done( "Sent invite" )
      ->then( sub {
         await_sync( $invitee, check => sub {
            my ( $body ) = @_;

            return 0 unless exists $body->{rooms}{invite}{$room_id};

            return 1;
         })
      })->then( sub {
         matrix_join_room( $invitee, $room_id )
            ->SyTest::pass_on_done( "Joined room" )
      })->then( sub {
         matrix_get_room_state( $invitee, $room_id,
            type      => "m.room.member",
            state_key => $invitee->user_id,
         )
      })->then( sub {
         my ( $member_state ) = @_;

         $member_state->{membership} eq "join" or
            die "Expected my membership to be 'join'";

         Future->done(1);
      });
   };

test "Uninvited users cannot join the room",
   # TODO: deprecated endpoint used in this test
   requires => [ local_user_fixture(),
                 inviteonly_room_fixture( creator => local_user_fixture() ) ],

   check => sub {
      my ( $uninvited, $room_id ) = @_;

      matrix_join_room( $uninvited, $room_id )
         ->main::expect_http_403;
   };

my $other_local_user_fixture = local_user_fixture();

test "Invited user can reject invite",
   # TODO: deprecated endpoint used in this test
   requires => [ local_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],
   do => \&invited_user_can_reject_invite;

test "Invited user can reject invite over federation",
   # TODO: deprecated endpoint used in this test
   requires => [ remote_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],
   do => \&invited_user_can_reject_invite;

test "Invited user can reject invite over federation several times",
   # TODO: deprecated endpoint used in this test
   # https://github.com/matrix-org/synapse/issues/1987
   requires => [ remote_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],
   do => sub {
      my ( $invitee, $creator, $room_id ) = @_;

      # we just do an invite/reject cycle three times
      my $runner = sub {
         return invited_user_can_reject_invite(
            $invitee, $creator, $room_id
           );
      };

      $runner->()
        ->then( $runner )
        ->then( $runner );
   };

sub invited_user_can_reject_invite
{
   my ( $invitee, $creator, $room_id ) = @_;

   matrix_invite_user_to_room_synced( $creator, $invitee, $room_id )
   ->then( sub {
      matrix_leave_room_synced( $invitee, $room_id )
   })->then( sub {
      # Leaving a room may 200 OK before it gets sent over federation, which
      # is to be expected given rate limits/backoff. Therefore, we need to
      # keep querying the state on the other end until it works.
      ( repeat_until_true {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.member",
            state_key => $invitee->user_id,
         )->then( sub {
            my ( $body ) = @_;
            log_if_fail "Membership body (want leave)", $body;
            return unless $body->{membership} eq "leave";
            Future->done(1);
         })
      })
   })->then( sub {
      matrix_sync( $invitee )
   })->then( sub {
      my ( $body ) = @_;

      # Check that invitee no longer sees the invite

      if( exists $body->{rooms} and exists $body->{rooms}{invite} ) {
         assert_json_object( $body->{rooms}{invite} );
         keys %{ $body->{rooms}{invite} } and die "Expected empty dictionary";
      }

      Future->done(1);
   });
}

test "Invited user can reject invite for empty room",
   # TODO: deprecated endpoint used in this test
   requires => [ local_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],
   do => \&invited_user_can_reject_invite_for_empty_room;

test "Invited user can reject invite over federation for empty room",
   # TODO: deprecated endpoint used in this test
   requires => [ remote_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],
   do => \&invited_user_can_reject_invite_for_empty_room;

sub invited_user_can_reject_invite_for_empty_room
{
   my ( $invitee, $creator, $room_id ) = @_;

   matrix_invite_user_to_room( $creator, $invitee, $room_id )
   ->then( sub {
      # wait for the leave to come down to make sure we're testing an empty room
      matrix_leave_room_synced( $creator, $room_id )
   })
   ->then( sub {
      matrix_leave_room( $invitee, $room_id )
   })->then( sub {
      matrix_sync( $invitee )
   })->then( sub {
      my ( $body ) = @_;

      # Check that invitee no longer sees the invite

      if( exists $body->{rooms} and exists $body->{rooms}{invite} ) {
         assert_json_object( $body->{rooms}{invite} );
         keys %{ $body->{rooms}{invite} } and die "Expected empty dictionary";
      }
      Future->done(1);
   });
}

test "Invited user can reject local invite after originator leaves",
   # TODO: deprecated endpoint used in this test
   requires => [ local_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],
   do => sub {
      my ( $invitee, $creator, $room_id ) = @_;

      matrix_invite_user_to_room( $creator, $invitee, $room_id )
      ->then( sub {
         # wait for the leave to come down to make sure we're testing an empty room
         matrix_leave_room_synced( $creator, $room_id );
      })->then( sub {
         matrix_leave_room( $invitee, $room_id );
      })->then( sub {
         # there's nobody left who can look at the room state, but the
         # important thing is that a /sync for the invitee should not include
         # the invite any more.
         matrix_sync( $invitee );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Sync body", $body;

         if( exists $body->{rooms} and exists $body->{rooms}{invite} ) {
            assert_json_object( $body->{rooms}{invite} );
            keys %{ $body->{rooms}{invite} } and die "Expected empty dictionary";
         }

         Future->done(1);
      });
   };

test "Invited user can see room metadata",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $invitee ) = @_;

      my $state_in_invite;

      Future->needs_all(
         matrix_put_room_state( $creator, $room_id,
            type => "m.room.name",
            content => { name => "The room name" },
         ),
         matrix_put_room_state( $creator, $room_id,
            type => "m.room.avatar",
            content => { url => "http://something" },
         ),
      )->then( sub {
         matrix_invite_user_to_room( $creator, $invitee, $room_id );
      })->then( sub {
         await_sync( $invitee, check => sub {
            my ( $body ) = @_;

            return 0 unless exists $body->{rooms}{invite}{$room_id};

            return $body->{rooms}{invite}{$room_id};
         })
      })->then( sub {
         my ( $body ) = @_;

         # invite_room_state is optional
         if( !$body->{invite_state} ) {
            return Future->done();
         }

         log_if_fail "Invite", $body;

         assert_json_list( $body->{invite_state}{events} );

         my %state_by_type = map {
            $_->{type} => $_
         } @{ $body->{invite_state}{events} };

         $state_by_type{$_} or die "Did not receive $_ state"
            for qw( m.room.join_rules m.room.name
                    m.room.avatar );

         my @futures = ();

         foreach my $event_type ( keys %state_by_type ) {
            push @futures, matrix_get_room_state( $creator, $room_id,
               type      => $event_type,
               state_key => $state_by_type{$event_type}{state_key},
            )->then( sub {
               my ( $room_content ) = @_;

               my $invite_content = $state_by_type{$event_type}{content};

               assert_deeply_eq( $room_content, $invite_content,
                  'invite content' );

               Future->done();
            });
         }

         Future->needs_all( @futures )
            ->then_done(1);
      });
   };

test "Remote invited user can see room metadata",
   requires => [ local_user_and_room_fixtures(), remote_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $invitee ) = @_;

      Future->needs_all(
         matrix_put_room_state( $creator, $room_id,
            type => "m.room.name",
            content => { name => "The room name" },
         ),
         matrix_put_room_state( $creator, $room_id,
            type => "m.room.avatar",
            content => { url => "http://something" },
         ),
      )->then( sub {
         matrix_invite_user_to_room_synced( $creator, $invitee, $room_id );
      })->then( sub {
         await_sync( $invitee, check => sub {
            my ( $body ) = @_;

            return 0 unless exists $body->{rooms}{invite}{$room_id};

            return $body->{rooms}{invite}{$room_id};
         });
      })->then( sub {
         my ( $body ) = @_;

         # invite_room_state is optional
         if( !$body->{invite_state} ) {
            return Future->done();
         }

         log_if_fail "Invite", $body;

         assert_json_list( $body->{invite_state}{events} );

         my %state_by_type = map {
            $_->{type} => $_
         } @{ $body->{invite_state}{events} };

         $state_by_type{$_} or die "Did not receive $_ state"
            for qw( m.room.join_rules m.room.name
                    m.room.avatar );

         my @futures = ();

         foreach my $event_type ( keys %state_by_type ) {
            push @futures, matrix_get_room_state( $creator, $room_id,
               type      => $event_type,
               state_key => $state_by_type{$event_type}{state_key},
            )->then( sub {
               my ( $room_content ) = @_;

               my $invite_content = $state_by_type{$event_type}{content};

               assert_deeply_eq( $room_content, $invite_content,
                  'invite content' );

               Future->done();
            });
         }

         Future->needs_all( @futures )
            ->then_done(1);
      });
   };

test "Users cannot invite themselves to a room",
   requires => [ local_user_and_room_fixtures() ],

   do => sub {
      my ( $creator, $room_id ) = @_;

      matrix_invite_user_to_room( $creator, $creator, $room_id )
         ->main::expect_http_403;
   };

test "Users cannot invite a user that is already in the room",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $invitee ) = @_;

      matrix_join_room( $invitee, $room_id )->then( sub {
         matrix_invite_user_to_room( $creator, $invitee, $room_id )
            ->main::expect_http_403;
      });
   };

multi_test "Test that we can be reinvited to a room we created",
   requires => [ local_user_fixture( with_events => 1 ), remote_user_fixture( with_events => 1 ),
                 qw( can_change_power_levels )],

   check => sub {
      my ( $user_1, $user_2 ) = @_;

      my $room_id;

      matrix_create_room( $user_1 )
         ->SyTest::pass_on_done( "User A created a room" )
      ->then( sub {
         ( $room_id ) = @_;

         matrix_put_room_state( $user_1, $room_id,
            type    => "m.room.join_rules",
            content => { join_rule => "invite" },
         )->SyTest::pass_on_done( "User A set the join rules to 'invite'" )
      })->then( sub {

         matrix_invite_user_to_room( $user_1, $user_2, $room_id )
            ->SyTest::pass_on_done( "User A invited user B" )
      })->then( sub {

         await_sync( $user_2, check => sub {
            my ( $body ) = @_;

            return 0 unless exists $body->{rooms}{invite}{$room_id};
            return $body->{rooms}{invite}{$room_id};
         })->SyTest::pass_on_done( "User B received the invite from A" )
      })->then( sub {

         matrix_join_room( $user_2, $room_id )
            ->SyTest::pass_on_done( "User B joined the room" )
      })->then( sub {

         matrix_change_room_power_levels( $user_1, $room_id, sub {
            my ( $levels ) = @_;

            $levels->{users}{ $user_2->user_id } = 100;
         })->SyTest::pass_on_done( "User A set user B's power level to 100" )
      })->then( sub {

         matrix_leave_room( $user_1, $room_id )
            ->SyTest::pass_on_done( "User A left the room" )
      })->then( sub {
         await_sync_timeline_contains( $user_2, $room_id,  check => sub {
            my ( $event ) = @_;
            return $event->{type} eq "m.room.member" &&
               $event->{content}->{membership} eq "leave";
         })->SyTest::pass_on_done( "User B received the leave event" )
      })->then( sub {

         matrix_invite_user_to_room( $user_2, $user_1, $room_id )
            ->SyTest::pass_on_done( "User B invited user A back to the room" )
      })->then( sub {

         await_sync( $user_1, check => sub {
            my ( $body ) = @_;

            return 0 unless exists $body->{rooms}{invite}{$room_id};
            return $body->{rooms}{invite}{$room_id};
         })->SyTest::pass_on_done( "User A received the invite from user B" )
      })->then( sub {

         retry_until_success {
            matrix_join_room( $user_1, $room_id )
         }->SyTest::pass_on_done( "User A joined the room" )
      })->then_done(1);
   };
