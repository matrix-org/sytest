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

            matrix_initialsync_room( $creator, $room_id )->then( sub {
               my ( $body ) = @_;

               assert_json_keys( $body, qw( state ));

               my ( $join_rules_event ) = first { $_->{type} eq "m.room.join_rules" } @{ $body->{state} };
               $join_rules_event or
                  die "Failed to find an m.room.join_rules event";

               $join_rules_event->{content}{join_rule} eq "invite" or
                  die "Expected join rule to be 'invite'";

               Future->done( $room_id );
            });
         });
      }
   )
}

multi_test "Can invite users to invite-only rooms",
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
   requires => [ local_user_fixture(),
                 inviteonly_room_fixture( creator => local_user_fixture() ) ],

   check => sub {
      my ( $uninvited, $room_id ) = @_;

      matrix_join_room( $uninvited, $room_id )
         ->main::expect_http_403;
   };

my $other_local_user_fixture = local_user_fixture();

test "Invited user can reject invite",
   requires => [ local_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],
   do => \&invited_user_can_reject_invite;

test "Invited user can reject invite over federation",
   requires => [ remote_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],
   do => \&invited_user_can_reject_invite;

test "Invited user can reject invite over federation several times",
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

   matrix_invite_user_to_room( $creator, $invitee, $room_id )
   ->then( sub {
      matrix_leave_room_synced( $invitee, $room_id )
   })->then( sub {
      matrix_get_room_state( $creator, $room_id,
         type      => "m.room.member",
         state_key => $invitee->user_id,
      );
   })->then( sub {
      my ( $body ) = @_;

      log_if_fail "Membership body", $body;
      $body->{membership} eq "leave" or
         die "Expected membership to be 'leave'";

      Future->done(1);
   })->then( sub {
      matrix_sync( $invitee )
   })->then( sub {
      my ( $body ) = @_;

      # Check that invitee no longer sees the invite

      assert_json_object( $body->{rooms}{invite} );
      keys %{ $body->{rooms}{invite} } and die "Expected empty dictionary";
      Future->done(1);
   });
}

test "Invited user can reject invite for empty room",
   requires => [ local_user_fixture(),
      do {
         my $creator = local_user_fixture();
         $creator, inviteonly_room_fixture( creator => $creator );
      }
   ],
   do => \&invited_user_can_reject_invite_for_empty_room;

test "Invited user can reject invite over federation for empty room",
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
      matrix_leave_room( $creator, $room_id )
   })
   ->then( sub {
      matrix_leave_room( $invitee, $room_id )
   })->then( sub {
      matrix_sync( $invitee )
   })->then( sub {
      my ( $body ) = @_;

      # Check that invitee no longer sees the invite

      assert_json_object( $body->{rooms}{invite} );
      keys %{ $body->{rooms}{invite} } and die "Expected empty dictionary";
      Future->done(1);
   });
}

test "Invited user can reject local invite after originator leaves",
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
         matrix_leave_room( $creator, $room_id );
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
         assert_json_object( $body->{rooms}{invite} );
         keys %{ $body->{rooms}{invite} } and die "Expected empty dictionary";
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
         matrix_invite_user_to_room( $creator, $invitee, $room_id );
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
