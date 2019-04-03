#use Data::Dump qw( pp );

my $invitee_email = 'lemurs@monkeyworld.org';

test "Can invite existing 3pid",
   requires => [ local_user_fixtures( 2 ), id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $id_server ) = @_;

      my $invitee_mxid = $invitee->user_id;

      my $room_id;

      $id_server->bind_identity( undef, "email", $invitee_email, $invitee )
      ->then( sub {
         matrix_create_and_join_room( [ $inviter ], visibility => "private" )
      })->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $inviter,
            method => "POST",
            uri    => "/r0/rooms/$room_id/invite",

            content => {
               id_server    => $id_server->name,
               medium       => "email",
               address      => $invitee_email,
            },
         );
      })->then( sub {
         matrix_get_room_state( $inviter, $room_id,
            type      => "m.room.member",
            state_key => $invitee_mxid,
         );
      })->on_done( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;
         assert_eq( $body->{membership}, "invite",
            'invited user membership' );
      });
   };

test "Can invite existing 3pid with no ops",
   requires => [ local_user_fixtures( 3 ), id_server_fixture() ],

   do => sub {
      my ( $creator, $inviter, $invitee, $id_server ) = @_;

      my $invitee_mxid = $invitee->user_id;

      my $room_id;

      $id_server->bind_identity( undef, "email", $invitee_email, $invitee )
      ->then( sub {
         matrix_create_and_join_room( [ $creator, $inviter ], visibility => "private", with_invite => 1 )
      })->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $inviter,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/invite",

            content => {
               id_server    => $id_server->name,
               medium       => "email",
               address      => $invitee_email,
            },
         );
      })->then( sub {
         matrix_get_room_state( $inviter, $room_id,
            type      => "m.room.member",
            state_key => $invitee_mxid,
         );
      })->on_done( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;
         assert_eq( $body->{membership}, "invite",
            'invited user membership' );
      });
   };

test "Can invite existing 3pid in createRoom",
   requires => [ local_user_fixtures( 2 ), id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $id_server ) = @_;

      my $invitee_mxid = $invitee->user_id;

      my $room_id;

      $id_server->bind_identity( undef, "email", $invitee_email, $invitee )
      ->then( sub {
         my $invite_info = {
            medium    => "email",
            address   => $invitee_email,
            id_server => $id_server->name,
         };
         matrix_create_room( $inviter, invite_3pid => [ $invite_info ] );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_get_room_state( $inviter, $room_id,
            type      => "m.room.member",
            state_key => $invitee_mxid,
         );
      })->on_done( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;
         assert_eq( $body->{membership}, "invite",
            'invited user membership' );
      });
   };


test "Can invite unbound 3pid",
   requires => [ local_user_fixtures( 2 ), $main::HOMESERVER_INFO[0],
                 id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      matrix_create_and_join_room( [ $inviter ], visibility => "private" )
      ->then( sub {
         my ( $room_id ) = @_;

         can_invite_unbound_3pid( $room_id, $inviter, $invitee, $hs_uribase, $id_server );
      });
   };

test "Can invite unbound 3pid over federation",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 $main::HOMESERVER_INFO[1], id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      matrix_create_and_join_room( [ $inviter ], visibility => "private", with_invite => 1 )
      ->then( sub {
         my ( $room_id ) = @_;

         can_invite_unbound_3pid( $room_id, $inviter, $invitee, $hs_uribase, $id_server );
      });
   };

test "Can invite unbound 3pid with no ops",
   requires => [ local_user_fixtures( 3 ), $main::HOMESERVER_INFO[0],
                 id_server_fixture() ],

   do => sub {
      my ( $creator, $inviter, $invitee, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      matrix_create_and_join_room( [ $creator, $inviter ], visibility => "private", with_invite => 1 )
      ->then( sub {
         my ( $room_id ) = @_;
         can_invite_unbound_3pid( $room_id, $inviter, $invitee, $hs_uribase, $id_server );
      });
   };

test "Can invite unbound 3pid over federation with no ops",
   requires => [ local_user_fixtures( 2 ), remote_user_fixture(),
                 $main::HOMESERVER_INFO[1], id_server_fixture() ],

   do => sub {
      my ( $creator, $inviter, $invitee, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      matrix_create_and_join_room( [ $creator, $inviter ], visibility => "private", with_invite => 1 )
      ->then( sub {
         my ( $room_id ) = @_;
         can_invite_unbound_3pid( $room_id, $inviter, $invitee, $hs_uribase, $id_server );
      });
   };

sub can_invite_unbound_3pid
{
   my ( $room_id, $inviter, $invitee, $hs_uribase, $id_server ) = @_;

   do_3pid_invite( $inviter, $room_id, $id_server->name, $invitee_email )
   ->then( sub {
      $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee );
   })->then( sub {
      matrix_get_room_state( $inviter, $room_id,
         type      => "m.room.member",
         state_key => $invitee->user_id,
      )
   })->then( sub {
      my ( $body ) = @_;

      log_if_fail "m.room.member invite", $body;
      assert_eq( $body->{third_party_invite}{display_name}, 'Bob', 'invite display name' );

      matrix_join_room( $invitee, $room_id )
   })->then( sub {
      matrix_get_room_state( $inviter, $room_id,
         type      => "m.room.member",
         state_key => $invitee->user_id,
      )
   })->followed_by( assert_membership( "join" ) );
}

test "Can invite unbound 3pid over federation with users from both servers",
   requires => [ local_user_fixture(), remote_user_fixture(), remote_user_fixture(),
                 $main::HOMESERVER_INFO[1], id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $joiner, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;
      my $room_id;

      matrix_create_and_join_room( [ $inviter, $joiner ], visibility => "private", with_invite => 1 )
      ->then( sub {
         ( $room_id ) = @_;

         do_3pid_invite( $inviter, $room_id, $id_server->name, $invitee_email )
      })->then( sub {
         await_event_for( $joiner, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.third_party_invite";

            return 1;
         })
      })->then( sub {
         $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee );
      })->then( sub {
         await_event_for( $inviter, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member";
            return unless $event->{state_key} eq $invitee->user_id;

            assert_eq( $event->{content}{membership},  "invite" );

            return 1;
         })
      })->then( sub {
         matrix_get_room_state( $inviter, $room_id,
            type      => "m.room.member",
            state_key => $invitee->user_id,
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "m.room.member invite", $body;
         assert_eq( $body->{third_party_invite}{display_name}, 'Bob', 'invite display name' );

         matrix_join_room( $invitee, $room_id )
      })->then( sub {
         await_event_for( $inviter, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member";
            return unless $event->{state_key} eq $invitee->user_id;

            assert_eq( $event->{content}{membership},  "join" );

            return 1;
         })
      })->then( sub {
         matrix_get_room_state( $inviter, $room_id,
            type      => "m.room.member",
            state_key => $invitee->user_id,
         )
      })->followed_by( assert_membership( "join" ) );
   };

test "Can accept unbound 3pid invite after inviter leaves",
   requires => [ local_user_fixtures( 3 ), $main::HOMESERVER_INFO[0],
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $other_member, $invitee, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      my $room_id;

      matrix_create_room( $inviter, visibility => "private" )
      ->then( sub {
         ( $room_id ) = @_;

          matrix_invite_user_to_room( $inviter, $other_member, $room_id );
      })->then( sub {
          matrix_join_room( $other_member, $room_id );
      })->then( sub {
         do_3pid_invite( $inviter, $room_id, $id_server->name, $invitee_email )
      })->then( sub {
         matrix_leave_room( $inviter, $room_id );
      })->then( sub {
         $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee );
      })->then( sub {
         matrix_join_room( $invitee, $room_id )
      })->then( sub {
         matrix_get_room_state( $other_member, $room_id,
            type      => "m.room.member",
            state_key => $invitee->user_id,
         )
      })->followed_by( assert_membership( "join" ) );
   };

test "Can accept third party invite with /join",
   requires => [ local_user_fixture(), local_user_fixture(),
                 $main::HOMESERVER_INFO[1], id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      my $room_id;

      matrix_create_room( $inviter, visibility => "private" )
      ->then( sub {
         ( $room_id ) = @_;

         do_3pid_invite( $inviter, $room_id, $id_server->name, $invitee_email )
      })->then( sub {
         matrix_get_room_state( $inviter, $room_id, )
      })->then( sub {
         my ( $body ) = @_;

         my $invite_event = first { $_->{type} eq "m.room.third_party_invite" } @$body or
            die "Could not find m.room.third_party_invite event";

         my $token = $invite_event->{state_key};

         my %req = (
            mxid   => $invitee->user_id,
            sender => $inviter->user_id,
            token  => $token,
         );

         $id_server->sign( \%req, ephemeral => 1 );

         matrix_join_room( $invitee, $room_id,
            third_party_signed => \%req
         );
      })->then( sub {
         matrix_get_room_state( $inviter, $room_id,
            type      => "m.room.member",
            state_key => $invitee->user_id,
         )
      })->followed_by( assert_membership( "join" ) );
   };

test "Uses consistent guest_access_token across requests",
   requires => [ local_user_and_room_fixtures(), local_user_and_room_fixtures(),
                 $main::HOMESERVER_INFO[1], id_server_fixture() ],

   do => sub {
      my ( $inviter1, $room1, $inviter2, $room2, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      Future->needs_all(
         do_3pid_invite( $inviter1, $room1, $id_server->name, $invitee_email ),
         do_3pid_invite( $inviter2, $room2, $id_server->name, $invitee_email ),
      )->then( sub {
         my $invites = $id_server->invites_for( "email", $invitee_email );

         log_if_fail "invites", $invites;
         assert_eq( scalar( @$invites ), 2, "Invite count" );
         assert_eq( $invites->[0]{guest_access_token}, $invites->[1]{guest_access_token}, "guest_access_tokens" );

         Future->done( 1 );
      });
   };

test "3pid invite join with wrong but valid signature are rejected",
   requires => [ local_user_fixtures( 2 ), $main::HOMESERVER_INFO[0],
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      invite_should_fail( $inviter, $invitee, $hs_uribase, $id_server, sub {
         $id_server->rotate_keys;
         $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee );
      });
   };

test "3pid invite join valid signature but revoked keys are rejected",
   requires => [ local_user_fixtures( 2 ), $main::HOMESERVER_INFO[0],
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      invite_should_fail( $inviter, $invitee, $hs_uribase, $id_server, sub {
         $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee,
            sub { $id_server->rotate_keys } );
      });
   };

test "3pid invite join valid signature but unreachable ID server are rejected",
   requires => [ local_user_fixtures( 2 ), $main::HOMESERVER_INFO[0],
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $info, $id_server ) = @_;
      my $hs_uribase = $info->client_location;

      invite_should_fail( $inviter, $invitee, $hs_uribase, $id_server, sub {
         $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee, sub {
            # Stop the server listening by closing any active connections and
            # taking its handle away

            foreach my $c ($id_server->children()) {
               if( $c->can( 'close' )) {
                  $c->close();
               }
            }
            $id_server->configure( handle => undef );
         });
      });
   };


sub invite_should_fail {
   my ( $inviter, $invitee, $hs_base_url, $id_server, $bind_sub ) = @_;

   my $room_id;

   matrix_create_room( $inviter, visibility => "private" )
   ->then( sub {
      ( $room_id ) = @_;
      log_if_fail "Created room id $room_id";
      do_3pid_invite( $inviter, $room_id, $id_server->name, $invitee_email )
   })->then( sub {
      $bind_sub->( $id_server );
   })->then( sub {
      matrix_join_room( $invitee, $room_id )
         ->main::expect_http_4xx
   })->then( sub {
      matrix_get_room_state( $inviter, $room_id,
         type      => "m.room.member",
         state_key => $invitee->user_id,
      )
   })->followed_by(assert_membership( undef ) );
}

sub assert_membership {
   my ( $expected_membership ) = @_;

   my $verifier = defined $expected_membership
      ? sub {
         my ( $f ) = @_;

         $f->then( sub {
            my ( $body ) = @_;

            log_if_fail "Body", $body;
            $body->{membership} eq $expected_membership or
               die "Expected invited user membership to be '$expected_membership'";

            Future->done( 1 );
         } )
      }
      : \&main::expect_http_error;
}

sub do_3pid_invite {
   my ( $inviter, $room_id, $id_server, $invitee_email ) = @_;

   do_request_json_for( $inviter,
      method  => "POST",
      uri     => "/r0/rooms/$room_id/invite",
      content => {
         id_server    => $id_server,
         medium       => "email",
         address      => $invitee_email,
      }
   )->then( sub {
      my ( $result ) = @_;
      log_if_fail "sent 3pid invite for $invitee_email to $id_server";
      Future->done( 1 );
   });
}
