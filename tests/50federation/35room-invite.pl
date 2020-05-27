use JSON qw( decode_json );


1 || test "Outbound federation rejects /invite responses which are not correctly signed",
   requires => [
      # TODO: create await_request_v2_invite to hande /v2/invite and thus
      # support other room versions here
      local_user_and_room_fixtures( room_opts => { room_version => "1" } ),
      $main::INBOUND_SERVER,
      federation_user_id_fixture(),
   ],

   do => sub {
      my ( $user, $room_id, $inbound_server, $invitee_id ) = @_;

      Future->needs_all(
         matrix_invite_user_to_room( $user, $invitee_id, $room_id )->
         # currently synapse fails with a 500 which is kinda stupid
         main::expect_http_error(),

         $inbound_server->await_request_invite( $room_id )->then( sub {
            my ( $req, undef ) = @_;

            my $body = $req->body_from_json;
            log_if_fail "Invitation", $body;


            # just send the invite back without signing it

            $req->respond_json(
               # /v1/invite has an extraneous [ 200, ... ] wrapper (fixed in /v2)
               [ 200, { event => $body } ]
            );

            Future->done;
         }),
      );
   };


foreach my $prefix ( qw( v1 v2 )) {
   my %room_opts;
   $room_opts{room_version} = "2" if $prefix eq 'v1';

   test "Outbound federation can send invites via $prefix API",
      requires => [
         local_user_and_room_fixtures( room_opts => \%room_opts ),
         $main::INBOUND_SERVER, federation_user_id_fixture()
      ],

      do => sub {
         my ( $user, $room_id, $inbound_server, $invitee_id ) = @_;

         my $await_func = "await_request_${prefix}_invite";
         Future->needs_all(
            $inbound_server->$await_func( $room_id )->then( sub {
               my ( $req, undef ) = @_;

               assert_eq( $req->method, "PUT",
                  'request method' );

               my $body = $req->body_from_json;
               log_if_fail "Invitation", $req->body_from_json;

               if( $prefix eq 'v2' ) {
                  assert_json_keys( $body, qw( room_version event ));
                  $body = $body->{event};
               }

               # this should be a member event
               assert_json_keys( $body, qw( origin room_id sender type ));

               assert_eq( $body->{type}, "m.room.member",
                  'event type' );
               assert_eq( $body->{origin}, $user->http->server_name,
                  'event origin' );
               assert_eq( $body->{room_id}, $room_id,
                  'event room_id' );
               assert_eq( $body->{sender}, $user->user_id,
                  'event sender' );

               assert_json_keys( $body, qw( content state_key ));

               assert_eq( $body->{content}{membership}, "invite",
                  'event content membership' );
               assert_eq( $body->{state_key}, $invitee_id,
                  'event state_key' );

               $inbound_server->datastore->sign_event( $body );

               my $resp = { event => $body };

               if( $prefix eq 'v1' ) {
                  # /v1/invite has an extraneous [ 200, ... ] wrapper (fixed in /v2)
                  $resp = [ 200, $resp ];
               }
               $req->respond_json( $resp );

               Future->done;
            }),

            matrix_invite_user_to_room( $user, $invitee_id, $room_id )
         );
      };
}

test "Inbound federation can receive invites via v1 API",
   requires => [ local_user_fixture( with_events => 1 ), $main::INBOUND_SERVER,
                 federation_user_id_fixture() ],

   do => sub {
      my ( $user, $inbound_server, $creator_id ) = @_;

      my $datastore = $inbound_server->datastore;

      my $room = SyTest::Federation::Room->new(
         datastore => $datastore,
      );

      $room->create_initial_events(
         server  => $inbound_server,
         creator => $creator_id,
      );

      invite_server_v1( $room, $creator_id, $user, $inbound_server );
   };


test "Inbound federation can receive invites via v2 API",
   requires => [ local_user_fixture( with_events => 1 ), $main::INBOUND_SERVER,
                 federation_user_id_fixture() ],

   do => sub {
      my ( $user, $inbound_server, $creator_id ) = @_;

      my $datastore = $inbound_server->datastore;

      my $room = SyTest::Federation::Room->new(
         datastore => $datastore,
      );

      $room->create_initial_events(
         server  => $inbound_server,
         creator => $creator_id,
      );

      invite_server_v2( $room, $creator_id, $user, $inbound_server );
   };


=head2 invite_server_v1

   invite_server_v1( $room, $creator_id, $user, $inbound_server )

Invite a server using the V1 API. See invite_server

=cut

sub invite_server_v1
{
   invite_server( @_, \&do_v1_invite_request )
}


=head2 invite_server_v2

   invite_server_v1( $room, $creator_id, $user, $inbound_server )

Invite a server using the V2 API. See invite_server

=cut

sub invite_server_v2
{
   invite_server( @_, \&do_v2_invite_request )
}

=head2 invite_server

   invite_server( $room, $creator_id, $user, $inbound_server, $do_invite_request )

Invite a server into the room using the given `do_invite_request` parameter to
actually send the invite request

=cut

sub invite_server
{
   my ( $room, $creator_id, $user, $inbound_server, $do_invite_request ) = @_;

   my $outbound_client = $inbound_server->client;
   my $first_home_server = $user->http->server_name;

   my $room_id = $room->room_id;

   my $invitation = $room->create_and_insert_event(
     type => "m.room.member",

     content   => { membership => "invite" },
     sender    => $creator_id,
     state_key => $user->user_id,
   );

   exists $invitation->{signatures}{ $inbound_server->server_name } or
     die "ARGH: I forgot to sign my own event";

   Future->needs_all(
     await_event_for( $user, filter => sub {
         my ( $event ) = @_;
         return $event->{type} eq "m.room.member" &&
                $event->{room_id} eq $room_id;
         }
     )->then( sub {
         my ( $event ) = @_;
         log_if_fail "Invitation event", $event;

         assert_eq( $event->{state_key}, $user->user_id,
            'event state_key' );
         assert_eq( $event->{content}{membership}, "invite",
            'event content membership' );

         Future->done(1);
     }),

     $do_invite_request->(
         $room, $first_home_server, $outbound_client, $invitation,
     )->then( sub {
         my ( $response ) = @_;

         log_if_fail "send invite response", $response;

         my $event = $response->{event};

         # Response should be the same event reflected back
         assert_eq( $event->{$_}, $invitation->{$_},
            "response $_" ) for qw( event_id origin room_id sender state_key type );

         # server should have signed it
         exists $event->{signatures}{$first_home_server} or
            die "Expected server to sign invitation";

         Future->done(1);
     }),
   );
}

=head2 do_v1_invite_request

   do_v1_invite_request( $room, $target_server, $outbound_client, $invitation )

Send an invite event via the V1 API

=cut

sub do_v1_invite_request
{
   my ( $room, $first_home_server, $outbound_client, $invitation ) = @_;

   my $room_id = $room->room_id;

   $outbound_client->do_request_json(
      method   => "PUT",
      hostname => $first_home_server,
      uri      => "/v1/invite/$room_id/$invitation->{event_id}",

      content => $invitation,
   )->then( sub {
      my ( $response ) = @_;

      # $response arrives with an extraneous layer of wrapping as the result of
      # a synapse implementation bug (matrix-org/synapse#1383).
      (ref $response eq "ARRAY") or die "V1 invite response must be an array";

      $response->[0] == 200 or
         die "Expected first response element to be 200";

      $response = $response->[1];

      Future->done( $response )
   })
}

=head2 do_v2_invite_request

   do_v2_invite_request( $room, $target_server, $outbound_client, $invitation )

Send an invite event via the V2 API

=cut

sub do_v2_invite_request
{
   my ( $room, $first_home_server, $outbound_client, $invitation ) = @_;

   my $room_id = $room->room_id;

   my $create_event = $room->get_current_state_event( "m.room.create" );
   my $room_version = $create_event->{content}{room_version} // "1";

   $outbound_client->do_request_json(
      method   => "PUT",
      hostname => $first_home_server,
      uri      => "/v2/invite/$room_id/$invitation->{event_id}",

      content => {
         event             => $invitation,
         room_version      => $room_version,
         invite_room_state => [],
      },
   )
}


foreach my $error_code ( 403, 500, -1 ) {
   # a temporary federation server which is shut down at the end of the test.
   # we use a temporary server because otherwise the remote server ends up on the
   # backoff list and subsequent tests fail.
   my $temp_federation_server_fixture = fixture(
      setup => sub {
         create_federation_server()->on_done(sub {
            log_if_fail "Started temporary federation server " . $_[0]->server_name;
         });
      },
      teardown => sub {
         my ($server) = @_;
         $server->close();
      }
   );

   test "Inbound federation can receive invite and reject when remote "
         . ( $error_code >= 0 ? "replies with a $error_code" :
             "is unreachable" ),
      requires => [ local_user_fixture( with_events => 1 ), $temp_federation_server_fixture ],

      do => sub {
         my ( $user, $federation_server ) = @_;

         my $creator_id = '@__ANON__:' . $federation_server->server_name;

         my $datastore = $federation_server->datastore;

         my $room = SyTest::Federation::Room->new(
            datastore => $datastore,
         );

         $room->create_initial_events(
            server  => $federation_server,
            creator => $creator_id,
         );

         my $room_id = $room->room_id;

         invite_server_v1( $room, $creator_id, $user, $federation_server )
         ->then( sub {
            if( $error_code < 0 ) {
               # now shut down the remote server, so that we get an 'unreachable'
               # error on make_leave
               log_if_fail "Stopping temporary fed server " . $federation_server->server_name;
               $federation_server->close();

               # close any connected sockets too, otherwise synapse will
               # just reuse the connection.
               foreach my $child ( $federation_server->children() ) {
                  # each child should be a Net::Async::HTTP::Server::Protocol
                  my $rh = $child->read_handle;
                  log_if_fail sprintf(
                     "closing HTTP connection from %s:%i", $rh->peerhost(), $rh->peerport(),
                  );
                  $child->close();
               }

               return matrix_leave_room( $user, $room_id );
            }
            else {
               Future->needs_all(
                  $federation_server->await_request_make_leave( $room_id, $user->user_id )->then( sub {
                     my ( $req, undef ) = @_;

                     assert_eq( $req->method, "GET", 'request method' );

                     $req->respond_json( {}, code => $error_code );

                     Future->done;
                  }),
                  matrix_leave_room( $user, $room_id )
               );
            }
         })->then( sub {
            matrix_sync( $user );
         })->then( sub {
            my ( $body ) = @_;

            log_if_fail "Sync body", $body;
            assert_json_object( $body->{rooms}{invite} );
            keys %{ $body->{rooms}{invite} } and die "Expected empty dictionary";
            Future->done(1);
         });
      };
}


test "Inbound federation rejects invites which are not signed by the sender",
   requires => [
      $main::OUTBOUND_CLIENT, local_user_fixture(), federation_user_id_fixture(),
   ],

   do => sub {
      my ( $outbound_client, $user, $sytest_user_id ) = @_;

      my $server_name = $user->server_name;
      my $datastore = $outbound_client->datastore;

      my $room = $datastore->create_room(
         creator => $sytest_user_id,
      );

      my $invite = $room->create_event(
         type => "m.room.member",
         content   => { membership => "invite" },
         sender    => $sytest_user_id,
         state_key => $user->user_id,
      );

      # remove the signature
      my %sigs = %{$invite->{signatures}};
      $invite->{signatures} = {};

      do_v1_invite_request( $room, $server_name, $outbound_client, $invite )
      ->main::expect_http_403()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "error body", $body;
         assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );

         # check it is accepted when the sig is reinstated
         $invite->{signatures} = \%sigs;
         do_v1_invite_request( $room, $server_name, $outbound_client, $invite );
      });
   };


test "Inbound federation can receive invite rejections",
   requires => [
      # TODO: create await_request_v2_invite to hande /v2/invite and thus
      # support other room versions here
      local_user_and_room_fixtures( room_opts => { room_version => "1" } ),
      $main::INBOUND_SERVER,
      $main::OUTBOUND_CLIENT,
      federation_user_id_fixture(),
   ],

   do => sub {
      my ( $user, $room_id, $inbound_server, $outbound_client, $invitee_id ) = @_;

      Future->needs_all(
         matrix_invite_user_to_room( $user, $invitee_id, $room_id ),

         $inbound_server->await_request_invite( $room_id )->then( sub {
            my ( $req, undef ) = @_;

            my $body = $req->body_from_json;
            log_if_fail "Invitation", $body;

            # accept the invite event and send it back
            $inbound_server->datastore->sign_event( $body );

            $req->respond_json(
               # /v1/invite has an extraneous [ 200, ... ] wrapper (fixed in /v2)
               [ 200, { event => $body } ]
            );

            Future->done;
         }),
      )->then( sub {
         # now let's reject the event: start by asking the server to build us a
         # leave event
         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $user->server_name,
            uri      => "/v1/make_leave/$room_id/$invitee_id",
         );
      })->then( sub {
         my ( $resp ) = @_;
         log_if_fail "/make_leave response", $resp;

         my $protoevent = $resp->{event};
         assert_json_keys( $protoevent, qw(
            event_id origin room_id sender type content state_key depth prev_events auth_events
         ));

         assert_eq( $protoevent->{type}, "m.room.member", 'event type' );
         assert_eq( $protoevent->{room_id}, $room_id, 'event room_id' );
         assert_eq( $protoevent->{sender}, $invitee_id, 'event sender' );
         assert_eq( $protoevent->{content}{membership}, "leave", 'event content membership' );
         assert_eq( $protoevent->{state_key}, $invitee_id, 'event state_key' );

         my ( $event, $event_id ) = $inbound_server->datastore->create_event(
            map { $_ => $protoevent->{$_} } qw(
               auth_events content depth prev_events room_id sender
               state_key type
            ),
         );

         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $user->server_name,
            uri      => "/v1/send_leave/$room_id/$event_id",
            content => $event,
           )
      })->then( sub {
         my ( $resp ) = @_;
         log_if_fail "/send_leave response", $resp;


         # /v1/send_join has an extraneous [200, ...] wrapper (see MSC1802)
         assert_json_list( $resp );
         $resp->[0] == 200 or
            die "Expected first response element to be 200";

         $resp = $resp->[1];
         assert_json_object( $resp );

         # now wait for the leave event to come down /sync to $user
         await_sync_timeline_contains(
            $user, $room_id, check => sub {
               my ( $event ) = @_;
               return unless $event->{type} eq "m.room.member";
               return unless $event->{content}{membership} eq "leave";
               return 1;
            }
         );
      });
   };

test "Inbound federation rejects incorrectly-signed invite rejections",
   requires => [
      # TODO: create await_request_v2_invite to hande /v2/invite and thus
      # support other room versions here
      local_user_and_room_fixtures( room_opts => { room_version => "1" } ),
      $main::INBOUND_SERVER,
      $main::OUTBOUND_CLIENT,
      federation_user_id_fixture(),
   ],

   do => sub {
      my ( $user, $room_id, $inbound_server, $outbound_client, $invitee_id ) = @_;

      my ( $leave_event, $leave_event_id );

      Future->needs_all(
         matrix_invite_user_to_room( $user, $invitee_id, $room_id ),

         $inbound_server->await_request_invite( $room_id )->then( sub {
            my ( $req, undef ) = @_;

            my $body = $req->body_from_json;
            log_if_fail "Invitation", $body;

            # accept the invite event and send it back
            $inbound_server->datastore->sign_event( $body );

            $req->respond_json(
               # /v1/invite has an extraneous [ 200, ... ] wrapper (fixed in /v2)
               [ 200, { event => $body } ]
            );

            Future->done;
         }),
      )->then( sub {
         # now let's reject the event: start by asking the server to build us a
         # leave event
         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $user->server_name,
            uri      => "/v1/make_leave/$room_id/$invitee_id",
         );
      })->then( sub {
         my ( $resp ) = @_;
         log_if_fail "/make_leave response", $resp;

         $leave_event = $resp->{event};

         $leave_event->{origin} = $outbound_client->server_name;
         $leave_event->{origin_server_ts} = $outbound_client->time_ms;
         $leave_event->{event_id} = $leave_event_id = $outbound_client->datastore->next_event_id();

         # let's start by sending it back without any signatures
         log_if_fail "Sending event with no signature", $leave_event;

         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $user->server_name,
            uri      => "/v1/send_leave/$room_id/$leave_event_id",
            content => $leave_event,
        );
      })->main::expect_http_403()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "unsigned event: error body", $body;
         assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );

         # try a fake signature
         $leave_event->{signatures} = {
            $outbound_client->server_name => {
               $outbound_client->datastore->key_id => "a" x 86,
            }
         };

         log_if_fail "Sending event with bad signature", $leave_event;
         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $user->server_name,
            uri      => "/v1/send_leave/$room_id/$leave_event_id",
            content  => $leave_event,
         );
      })->main::expect_http_403()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "bad signature: error body", $body;
         assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );

         # make sure that it gets accepted once we sign it
         $outbound_client->datastore->sign_event( $leave_event );

         log_if_fail "Sending correctly-signed leave event", $leave_event;
         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $user->server_name,
            uri      => "/v1/send_leave/$room_id/$leave_event_id",
            content  => $leave_event,
           );
      })->then( sub {
         my ( $resp ) = @_;

         # /v1/send_leave has an extraneous [200, ...] wrapper (see MSC1802)
         assert_json_list( $resp );
         $resp->[0] == 200 or
            die "Expected first response element to be 200";

         $resp = $resp->[1];
         assert_json_object( $resp );

         # now wait for the leave event to come down /sync to $user
         await_sync_timeline_contains(
            $user, $room_id, check => sub {
               my ( $event ) = @_;
               return unless $event->{type} eq "m.room.member";
               return unless $event->{content}{membership} eq "leave";
               return 1;
            }
         );
      });
   };

test "Inbound /v1/send_leave rejects leaves from other servers",
   # we start by getting the two test servers to join a room, and join it
   # ourselves; we then get the second server to leave and rejoin the room, and
   # replay the second server's leave to the first.

   requires => [
      $main::OUTBOUND_CLIENT,
      $main::INBOUND_SERVER,
      local_user_fixture(),
      remote_user_fixture(),
      federation_user_id_fixture(),
      qw( can_join_remote_room_by_alias ),
   ],

   do => sub {
      my ( $outbound_client, $inbound_server, $creator_user, $joiner_user, $federation_user_id ) = @_;
      my ( $room, $room_id );
      my ( $leave_event );

      matrix_create_and_join_room(
         [ $creator_user, $joiner_user ],
      )->then( sub {
         ( $room_id ) = @_;

         # we join via the joiner_user to make sure that that server receives our join
         # before the user leaves (otherwise we might not get a copy of the leave)
         $outbound_client->join_room(
            server_name => $joiner_user->server_name,
            room_id => $room_id,
            user_id => $federation_user_id,
         );
      })->then( sub {
         ( $room ) = @_;
         log_if_fail "All users joined room; initiating leave";
         Future->needs_all(
            matrix_leave_room( $joiner_user, $room_id ),

            # make sure that the leave propagates back to the sytest server...
            $inbound_server->await_event(
               "m.room.member", $room_id, sub {
                  my ( $ev ) = @_;
                  log_if_fail "received event over federation", $ev;
                  return $ev->{state_key} eq $joiner_user->user_id &&
                     $ev->{content}{membership} eq 'leave';
               }
            ),

            # and to server-0 (it can get held up behind the sytest server's
            # join, which triggers a different bug where rejoins aren't sent
            # out over federation)
            await_sync_timeline_contains(
               $creator_user, $room_id, check => sub {
                  my ( $ev ) = @_;
                  log_if_fail "creator user received event over sync", $ev;
                  return $ev->{type} eq 'm.room.member' &&
                     $ev->{state_key} eq $joiner_user->user_id &&
                     $ev->{content}{membership} eq 'leave';
               },
            ),
         );
      })->then( sub {
         $leave_event = $room->get_current_state_event( 'm.room.member', $joiner_user->user_id );
         die "can't find leaving membership event" unless $leave_event;
         log_if_fail "Got leave event for second user", $leave_event;

         # now that we've got the leave event, rejoin
         Future->needs_all(
            matrix_join_room( $joiner_user, $room_id, server_name => $creator_user->server_name ),
            $inbound_server->await_event(
               "m.room.member", $room_id, sub {
                  my ( $ev ) = @_;
                  log_if_fail "received event", $ev;
                  return $ev->{state_key} eq $joiner_user->user_id &&
                     $ev->{content}{membership} eq 'join';
               }
            ),
         );
      })->then( sub {
         log_if_fail "Second user rejoined room; now replaying leave";
         # now replay the leave via /send_leave
         my $event_id = $room->id_for_event( $leave_event );
         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $creator_user->server_name,
            uri      => "/v1/send_leave/$room_id/$event_id",
            content  => $leave_event,
         );
      })->main::expect_http_403()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "error body", $body;
         assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );
         Future->done;
      });
   },

   # this test is a bit slooow
   timeout => 20;

test "Inbound federation rejects invites which include invalid JSON for room version 6",
   requires => [
      $main::OUTBOUND_CLIENT, local_user_fixture(), federation_user_id_fixture(),
   ],

   do => sub {
      my ( $outbound_client, $user, $sytest_user_id ) = @_;

      my $server_name = $user->server_name;
      my $datastore = $outbound_client->datastore;

      my $room = $datastore->create_room(
         creator => $sytest_user_id,
         room_version => "6",
      );

      my $invite = $room->create_event(
         type => "m.room.member",
         content   => {
            membership => "invite",
            bad_val => 1.1,
         },
         sender    => $sytest_user_id,
         state_key => $user->user_id,
      );

      # Note that only v2 supports providing different room versions.
      do_v2_invite_request( $room, $server_name, $outbound_client, $invite )
      ->main::expect_bad_json;
   };

test "Outbound federation rejects invite response which include invalid JSON for room version 6",
   requires => [
      local_user_and_room_fixtures( room_opts => { room_version => "6" } ),
      $main::INBOUND_SERVER,
      $main::OUTBOUND_CLIENT,
      federation_user_id_fixture(),
   ],

   do => sub {
      my ($user, $room_id, $inbound_server, $outbound_client, $invitee_id) = @_;

      Future->needs_all(
         matrix_invite_user_to_room($user, $invitee_id, $room_id),

         $inbound_server->await_request_v2_invite($room_id)->then(sub {
            my ($req, undef) = @_;

            my $body = $req->body_from_json;
            log_if_fail "Invitation", $body;

            my $invite = $body->{event};
            # Add a bad value into the response.
            $invite->{bad_val} = 1.1;

            log_if_fail "Invitation 2", $invite;

            # accept the invite event and send it back
            $inbound_server->datastore->sign_event($invite);

            $req->respond_json(
               { event => $invite }
            );

            Future->done;
         }),
      )->main::expect_bad_json;
   };

test "Inbound federation rejects invite rejections which include invalid JSON for room version 6",
   requires => [
      local_user_and_room_fixtures( room_opts => { room_version => "6" } ),
      $main::INBOUND_SERVER,
      $main::OUTBOUND_CLIENT,
      federation_user_id_fixture(),
   ],

   do => sub {
      my ( $user, $room_id, $inbound_server, $outbound_client, $invitee_id ) = @_;

      Future->needs_all(
         matrix_invite_user_to_room( $user, $invitee_id, $room_id ),

         $inbound_server->await_request_v2_invite( $room_id )->then( sub {
            my ( $req, undef ) = @_;

            my $body = $req->body_from_json;
            log_if_fail "Invitation", $body;

            my $invite = $body->{event};

            # accept the invite event and send it back
            $inbound_server->datastore->sign_event( $invite );

            $req->respond_json(
               { event => $invite }
            );

            Future->done;
         }),
      )->then( sub {
         # now let's reject the event: start by asking the server to build us a
         # leave event
         #
         # Note that it doesn't make sense to try to use a bad JSON value here
         # since the endpoint doesn't accept any JSON anyway.
         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $user->server_name,
            uri      => "/v1/make_leave/$room_id/$invitee_id",
         );
      })->then( sub {
         my ( $resp ) = @_;
         log_if_fail "/make_leave response", $resp;

         my $protoevent = $resp->{event};
         assert_json_keys( $protoevent, qw(
            origin room_id sender type content state_key depth prev_events auth_events
         ));

         assert_eq( $protoevent->{type}, "m.room.member", 'event type' );
         assert_eq( $protoevent->{room_id}, $room_id, 'event room_id' );
         assert_eq( $protoevent->{sender}, $invitee_id, 'event sender' );
         assert_eq( $protoevent->{content}{membership}, "leave", 'event content membership' );
         assert_eq( $protoevent->{state_key}, $invitee_id, 'event state_key' );

         my ( $event, $event_id ) = $inbound_server->datastore->create_event(
            map { $_ => $protoevent->{$_} } qw(
               auth_events content depth prev_events room_id sender
               state_key type
            ),
         );

         my %event = (
            (map {$_ => $protoevent->{$_}} qw(
               auth_events content depth prev_events room_id sender
               state_key type)),

            origin           => $outbound_client->server_name,
            origin_server_ts => $inbound_server->time_ms,
         );
         # Insert a "bad" value into the send leave, in this case a float.
         ${event}{contents}{bad_val} = 1.1;

         $inbound_server->datastore->sign_event( \%event );

         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $user->server_name,
            uri      => "/v2/send_leave/$room_id/xxx",
            content => \%event,
           )
      })->main::expect_bad_json;
   };
