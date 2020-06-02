use JSON qw( decode_json );
use List::UtilsBy qw( partition_by extract_by );

use SyTest::Federation::Room;

my %STATE_EVENT_TYPES = map {$_=>1} qw (
   m.room.create
   m.room.member
   m.room.power_levels
   m.room.join_levels
   m.room.history_visibility
);

# check that the given event is valid
# (ideally would check that it is correctly signed and hashed, but that is TODO)
sub assert_is_valid_pdu {
   my ( $event ) = @_;

   assert_json_keys( $event, qw(
      auth_events content depth hashes origin origin_server_ts
      prev_events room_id sender signatures type
   ));

   assert_json_list( $event->{auth_events} );
   assert_json_number( $event->{depth} );
   assert_json_object( $event->{hashes} );

   assert_json_string( $event->{origin} );

   assert_json_number( $event->{origin_server_ts} );
   assert_json_list( $event->{prev_events} );

   assert_json_string( $event->{room_id} );
   assert_json_string( $event->{sender} );
   assert_json_object( $event->{signatures} );
   assert_json_string( $event->{type} );

   # for event types which are known to be state events, check that they
   # have the relevant keys
   if ( $STATE_EVENT_TYPES{ $event->{type} }) {
      assert_json_keys( $event, qw(
         state_key
      ));

      assert_json_string( $event->{state_key} );
   }

   # TODO: Check signatures and hashes

   # TODO: check the event id is valid in room v1, v2, and check it is absent
   # in room v3 and later
}
push our @EXPORT, qw( assert_is_valid_pdu );

foreach my $versionprefix ( qw( v1 v2 ) ) {
   test "Outbound federation can query $versionprefix /send_join",
      requires => [ local_user_fixture(), $main::INBOUND_SERVER,
                    federation_user_id_fixture() ],

      do => sub {
         my ( $user, $inbound_server, $creator_id ) = @_;

         my $local_server_name = $inbound_server->server_name;
         my $datastore         = $inbound_server->datastore;

         my $room_alias = "#50fed-room-alias:$local_server_name";
         my $room = $datastore->create_room(
            creator => $creator_id,
            alias   => $room_alias,
         );

         my $room_id = $room->room_id;

         my $await_request_send_join;

         if( $versionprefix eq "v1" ) {
            # We need to use the `_reject_v2` form here as otherwise SyTest
            # will respond to /v2/send_join and v1 endpoint will never get
            # called.
            $await_request_send_join =
               $inbound_server->await_request_v1_send_join_reject_v2($room_id );
         }
         elsif( $versionprefix eq "v2" ) {
            $await_request_send_join = $inbound_server->await_request_v2_send_join( $room_id );
         }

         Future->needs_all(
            # Await PDU?

            $inbound_server->await_request_make_join( $room_id, $user->user_id )->then( sub {
               my ( $req, $room_id, $user_id ) = @_;

               my $proto = $room->make_join_protoevent(
                  user_id => $user_id,
               );

               $proto->{origin}           = $inbound_server->server_name;
               $proto->{origin_server_ts} = $inbound_server->time_ms;

               $req->respond_json( {
                  event => $proto,
               } );

               Future->done;
            }),

            $await_request_send_join->then( sub {
               my ( $req, $room_id, $event_id ) = @_;

               $req->method eq "PUT" or
                  die "Expected send_join method to be PUT";

               my $event = $req->body_from_json;
               log_if_fail "send_join event", $event;

               my @auth_chain = $datastore->get_auth_chain_events(
                  map { $_->[0] } @{ $event->{auth_events} }
               );

               my $response = {
                  auth_chain => \@auth_chain,
                  state      => [ $room->current_state_events ],
               };

               if( $versionprefix eq "v1" ) {
                  # /v1/send_join has an extraneous [200, ...] wrapper (see MSC1802)
                  $response = [ 200, $response ];
               }

               $req->respond_json($response);

               log_if_fail "send_join response", $response;

               Future->done;
            }),

            do_request_json_for( $user,
               method => "POST",
               uri    => "/r0/join/$room_alias",

               content => {},
            )->then( sub {
               my ( $body ) = @_;
               log_if_fail "Join response", $body;

               assert_json_keys( $body, qw( room_id ));

               $body->{room_id} eq $room_id or
                  die "Expected room_id to be $room_id";

               matrix_get_my_member_event( $user, $room_id )
            })->then( sub {
               my ( $event ) = @_;

               # The joining HS (i.e. the SUT) should have invented the event ID
               # for my membership event.

               # TODO - sanity check the $event

               Future->done(1);
            }),
         )
      };
}


test "Outbound federation passes make_join failures through to the client",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER,
                 federation_user_id_fixture(),
                ],

   do => sub {
      my ( $user, $inbound_server, $creator_id) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;
      my $room_id           = $datastore->next_room_id;

      my $test_room_version = 'sytest-room-ver';

      # We'll have to jump through the extra hoop of using the directory
      # service first, because we can't join a remote room by room ID alone
      my $room_alias = "#unsupported-room-ver:$local_server_name";
      $datastore->{room_aliases}{$room_alias} = $room_id;

      Future->needs_all(
         $inbound_server->await_request_make_join( $room_id, $user->user_id )->then( sub {
            my ( $req, $room_id, $user_id ) = @_;
            $req->respond_json(
               {
                  errcode => "M_TEST_ERROR_CODE",
                  error => "denied!",
               },
               code => 400,
            );
            Future->done;
         }),

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/join/$room_alias",

            content => {},
         )->main::expect_http_400
         ->then( sub {
            my ( $response ) = @_;
            my $body = decode_json( $response->content );
            log_if_fail "Join error response", $body;

            assert_eq( $body->{errcode}, "M_TEST_ERROR_CODE", 'responsecode' );
            Future->done(1);
         }),
      )
   };


foreach my $versionprefix ( qw ( v1 v2 ) ) {
   test "Inbound federation can receive $versionprefix /send_join",
      requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER,
                    local_user_and_room_fixtures( room_opts => { room_version => "1" } ),
                    federation_user_id_fixture() ],

      do => sub {
         my ( $outbound_client, $inbound_server, $creator, $room_id, $user_id ) = @_;
         my $first_home_server = $creator->server_name;

         my $local_server_name = $outbound_client->server_name;
         my $datastore         = $inbound_server->datastore;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/make_join/$room_id/$user_id",
         )->then( sub {
            my ( $body ) = @_;
            log_if_fail "make_join body", $body;

            assert_json_keys( $body, qw( event ));

            my $protoevent = $body->{event};

            assert_json_keys( $protoevent, qw(
               auth_events content depth room_id sender state_key type
            ));

            assert_json_nonempty_list( my $auth_events = $protoevent->{auth_events} );
            foreach my $auth_event ( @$auth_events ) {
               assert_json_list( $auth_event );
               @$auth_event == 2 or
                  die "Expected auth_event list element to have 2 members";

               assert_json_string( $auth_event->[0] );  # id
               assert_json_object( $auth_event->[1] );  # hashes
            }

            assert_json_nonempty_list( $protoevent->{prev_events} );

            assert_json_number( $protoevent->{depth} );

            $protoevent->{room_id} eq $room_id or
               die "Expected 'room_id' to be $room_id";
            $protoevent->{sender} eq $user_id or
               die "Expected 'sender' to be $user_id";
            $protoevent->{state_key} eq $user_id or
               die "Expected 'state_key' to be $user_id";
            $protoevent->{type} eq "m.room.member" or
               die "Expected 'type' to be 'm.room.member'";

            assert_json_keys( my $content = $protoevent->{content}, qw( membership ) );
            $content->{membership} eq "join" or
               die "Expected 'membership' to be 'join'";

            my %event = (
               ( map { $_ => $protoevent->{$_} } qw(
                  auth_events content depth prev_events room_id sender
                  state_key type ) ),

               event_id         => $datastore->next_event_id,
               origin           => $local_server_name,
               origin_server_ts => $inbound_server->time_ms,
            );

            $datastore->sign_event( \%event );

            $outbound_client->do_request_json(
               method   => "PUT",
               hostname => $first_home_server,
               uri      => "/$versionprefix/send_join/$room_id/$event{event_id}",

               content => \%event,
            )
         })->then( sub {
            my ( $response ) = @_;

            if( $versionprefix eq "v1" ) {
               # /v1/send_join has an extraneous [200, ...] wrapper (see MSC1802)
               $response->[0] == 200 or
                  die "Expected first response element to be 200";

               $response = $response->[1];
            }

            assert_json_keys( $response, qw( auth_chain state ));

            assert_json_nonempty_list( $response->{auth_chain} );
            my @auth_chain = @{ $response->{auth_chain} };

            log_if_fail "Auth chain", \@auth_chain;

            foreach my $event ( @auth_chain ) {
               assert_is_valid_pdu( $event );
               $event->{room_id} eq $room_id or
                  die "Expected auth_event room_id to be $room_id";
            }

            # Annoyingly, the "auth chain" isn't specified to arrive in any
            # particular order. We'll have to keep walking it incrementally.

            my %accepted_authevents;
            while( @auth_chain ) {
               my @accepted = extract_by {
                  $inbound_server->auth_check_event( $_, \%accepted_authevents )
               } @auth_chain;

               unless( @accepted ) {
                  log_if_fail "Unacceptable auth chain", \@auth_chain;

                  die "Unable to find any more acceptable auth_chain events";
               }

               $accepted_authevents{$_->{event_id}} = $_ for @accepted;
            }

            assert_json_nonempty_list( $response->{state} );
            my %state = partition_by { $_->{type} } @{ $response->{state} };

            log_if_fail "State", \%state;

            # TODO: lots more checking. Requires spec though
            Future->done(1);
         });
      };
}


test "Inbound /v1/make_join rejects remote attempts to join local users to rooms",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_fixture(),
                 local_user_fixture(),
               ],

   do => sub {
      my ( $outbound_client, $creator_user, $user ) = @_;
      my $first_home_server = $creator_user->server_name;

      my $user_id = $user->user_id;

      matrix_create_room(
         $creator_user,
         room_version => "1",
      )->then( sub {
         my ( $room_id ) = @_;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/make_join/$room_id/$user_id",
         );
      })->main::expect_http_403()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "error body", $body;
         assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );
         Future->done( 1 );
      });
   };


test "Inbound /v1/send_join rejects incorrectly-signed joins",
   requires => [
      $main::OUTBOUND_CLIENT,
      local_user_fixture(),
      federation_user_id_fixture(),
   ],

   do => sub {
      my ( $outbound_client, $creator_user, $user_id ) = @_;
      my $sytest_server_name = $outbound_client->server_name;
      my $server_name = $creator_user->server_name;
      my $room_id;
      my $join_event;

      matrix_create_room(
         $creator_user,
      )->then( sub {
         ( $room_id ) = @_;

         $outbound_client->make_join(
            server_name => $server_name,
            room_id     => $room_id,
            user_id     => $user_id,
         );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "make_join body", $body;

         my $room_version = $body->{room_version} // 1;

         $join_event = $body->{event};

         $join_event->{origin} = $sytest_server_name;
         $join_event->{origin_server_ts} = $outbound_client->time_ms;

         if( $room_version eq '1' || $room_version eq '2' ) {
            # room v1/v2: assign an event id
            $join_event->{event_id} = $outbound_client->datastore->next_event_id();
         }

         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $server_name,
            uri      => "/v1/send_join/$room_id/xxx",
            content  => $join_event,
         );
      })->main::expect_http_403()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "unsigned event: error body", $body;
         assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );

         # try a fake signature
         $join_event->{signatures} = {
            $sytest_server_name => {
               $outbound_client->datastore->key_id => "a" x 86,
            },
         };

         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $server_name,
            uri      => "/v1/send_join/$room_id/xxx",
            content  => $join_event,
         );
      })->main::expect_http_403()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "bad signature: error body", $body;
         assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );

         # TODO: it would be nice to test that we reject a join event, sent
         # from server A, for a user on server A, with a signature from server
         # B (and not A). That probably entails spinning up a second test
         # federation server to partake in our conspiracy.

         # make sure that it gets accepted once we sign it
         $outbound_client->datastore->sign_event( $join_event );

         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $server_name,
            uri      => "/v1/send_join/$room_id/xxx",
            content  => $join_event,
         );

      })->then( sub {
         my ( $response ) = @_;

         # /v1/send_join has an extraneous [200, ...] wrapper (see MSC1802)
         $response->[0] == 200 or
            die "Expected first response element to be 200";

         $response = $response->[1];

         assert_json_keys( $response, qw( auth_chain state ));

         Future->done( 1 );
      });
   };


test "Inbound /v1/send_join rejects joins from other servers",
   # we start by getting the two test servers to join a room, and join it ourselves;
   # we then get the second server to leave the room, and replay the second server's
   # join to the first.

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
      my ( $join_event );

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

         $join_event = $room->get_current_state_event( 'm.room.member', $joiner_user->user_id );
         die "can't find joining membership event" unless $join_event;

         log_if_fail "Found join event", $join_event;

         Future->needs_all(
            matrix_leave_room( $joiner_user, $room_id ),

            # make sure that the leave propagates back to server-0
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
         log_if_fail "Second user left room; now replaying join";

         my $event_id = $room->id_for_event( $join_event );
         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $creator_user->server_name,
            uri      => "/v1/send_join/$room_id/$event_id",
            content  => $join_event,
         );
      })->main::expect_http_403()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "error body", $body;
         assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );

         Future->done;
      });
   };


test "Inbound federation rejects remote attempts to kick local users to rooms",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_fixture(),
               ],

   do => sub {
      my ( $outbound_client, $creator_user ) = @_;
      my $first_home_server = $creator_user->server_name;

      my $user_id = $creator_user->user_id;

      matrix_create_room(
         $creator_user,
      )->then( sub {
         my ( $room_id ) = @_;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/make_leave/$room_id/$user_id",
         );
      })->main::expect_http_403()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "error body", $body;
         assert_eq( $body->{errcode}, "M_FORBIDDEN", 'responsecode' );
         Future->done( 1 );
      });
   };


test "Inbound federation rejects attempts to join v1 rooms from servers without v1 support",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_fixture(),
                 federation_user_id_fixture(),
               ],

   do => sub {
      my ( $outbound_client, $creator_user, $user_id ) = @_;
      my $first_home_server = $creator_user->server_name;

      matrix_create_room(
         $creator_user,
         room_version => "1",
      )->then( sub {
         my ( $room_id ) = @_;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/make_join/$room_id/$user_id",
            params   => {
               ver => [qw/2 abc def/],
            },
         );
      })->main::expect_http_400()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "error body", $body;
         assert_eq( $body->{errcode}, "M_INCOMPATIBLE_ROOM_VERSION", 'responsecode' );
         assert_eq( $body->{room_version}, "1", 'room_version' );
         Future->done( 1 );
      });
   };


test "Inbound federation rejects attempts to join v2 rooms from servers lacking version support",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_fixture(),
                 federation_user_id_fixture(),
                 qw( can_create_versioned_room ) ],

   do => sub {
      my ( $outbound_client, $creator_user, $user_id ) = @_;
      my $first_home_server = $creator_user->server_name;

      matrix_create_room(
         $creator_user,
         room_version => '2',
      )->then( sub {
         my ( $room_id ) = @_;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/make_join/$room_id/$user_id",
         );
      })->main::expect_http_400()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "error body", $body;
         assert_eq( $body->{errcode}, "M_INCOMPATIBLE_ROOM_VERSION", 'responsecode' );
         assert_eq( $body->{room_version}, '2', 'room_version' );
         Future->done( 1 );
      });
   };


test "Inbound federation rejects attempts to join v2 rooms from servers only supporting v1",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_fixture(),
                 federation_user_id_fixture(),
                 qw( can_create_versioned_room ) ],

   do => sub {
      my ( $outbound_client, $creator_user, $user_id ) = @_;
      my $first_home_server = $creator_user->server_name;

      matrix_create_room(
         $creator_user,
         room_version => '2',
      )->then( sub {
         my ( $room_id ) = @_;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/make_join/$room_id/$user_id",
            params   => {
               ver => ["1"],
            },
         );
      })->main::expect_http_400()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         log_if_fail "error body", $body;
         assert_eq( $body->{errcode}, "M_INCOMPATIBLE_ROOM_VERSION", 'responsecode' );
         assert_eq( $body->{room_version}, '2', 'room_version' );
         Future->done( 1 );
      });
   };


test "Inbound federation accepts attempts to join v2 rooms from servers with support",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_fixture(),
                 federation_user_id_fixture(),
                 qw( can_create_versioned_room ) ],

   do => sub {
      my ( $outbound_client, $creator_user, $user_id ) = @_;
      my $first_home_server = $creator_user->server_name;

      matrix_create_room(
         $creator_user,
         room_version => '2',
      )->then( sub {
         my ( $room_id ) = @_;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/make_join/$room_id/$user_id",
            params   => {
               ver => [qw/abc 2 def/],
            },
         );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "make_join body", $body;

         assert_json_keys( $body, qw( event room_version ));

         assert_eq( $body->{room_version}, '2', 'room_version' );
         Future->done( 1 );
      });
   };


test "Outbound federation correctly handles unsupported room versions",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER,
                 federation_user_id_fixture(),
                 qw( can_create_versioned_room ) ],

   do => sub {
      my ( $user, $inbound_server, $creator_id ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;
      my $room_id           = $datastore->next_room_id;

      my $test_room_version = 'sytest-room-ver';

      my $room_alias = "#unsupported-room-ver:$local_server_name";
      $datastore->{room_aliases}{$room_alias} = $room_id;

      Future->needs_all(
         $inbound_server->await_request_make_join( $room_id, $user->user_id )->then( sub {
            my ( $req, $room_id, $user_id ) = @_;
            $req->respond_json({
               errcode => "M_INCOMPATIBLE_ROOM_VERSION",
               error => "y u no upgrade",
               room_version => 'sytest-room-ver',
            },
               code => 400,
            );
            Future->done;
         }),

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/join/$room_alias",

            content => {},
         )->main::expect_http_400
         ->then( sub {
            my ( $response ) = @_;
            my $body = decode_json( $response->content );
            log_if_fail "Join error response", $body;

            assert_eq( $body->{errcode}, "M_INCOMPATIBLE_ROOM_VERSION", 'responsecode' );
            assert_eq( $body->{room_version}, 'sytest-room-ver', 'room_version' );
            Future->done(1);
         }),
      )
   };


test "A pair of servers can establish a join in a v2 room",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_create_versioned_room can_join_remote_room_by_alias ),
               ],

   do => sub {
      my ( $creator_user, $joiner_user ) = @_;

      matrix_create_and_join_room(
         [ $creator_user, $joiner_user ],
         room_version => '2',
        );
   };


test "Outbound federation rejects send_join responses with no m.room.create event",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER,
                 federation_user_id_fixture() ],

   do => sub {
      my ( $user, $inbound_server, $creator_id ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $room_alias = "#no_create_event:$local_server_name";
      my $room = $datastore->create_room(
         creator => $creator_id,
         alias   => $room_alias,
      );

      my $room_id = $room->room_id;

      Future->needs_all(
         $inbound_server->await_request_make_join( $room_id, $user->user_id )->then( sub {
            my ( $req, $room_id, $user_id ) = @_;

            my $proto = $room->make_join_protoevent(
               user_id => $user_id,
            );

            $proto->{origin}           = $inbound_server->server_name;
            $proto->{origin_server_ts} = $inbound_server->time_ms;

            $req->respond_json( {
               event => $proto,
            } );

            log_if_fail "make_join resp", $proto;

            Future->done;
         }),

         $inbound_server->await_request_v1_send_join_reject_v2( $room_id )->then( sub {
            my ( $req, $room_id, $event_id ) = @_;

            $req->method eq "PUT" or
               die "Expected send_join method to be PUT";

            my $event = $req->body_from_json;
            log_if_fail "send_join event", $event;

            my @auth_chain = $datastore->get_auth_chain_events(
               map { $_->[0] } @{ $event->{auth_events} }
            );

            # filter out the m.room.create event
            @auth_chain = grep { $_->{type} ne 'm.room.create' } @auth_chain;

            $req->respond_json(
               # /v1/send_join has an extraneous [200, ...] wrapper (see MSC1802)
               my $response = [ 200, {
                  auth_chain => \@auth_chain,
                  state      => [ $room->current_state_events ],
               } ]
            );

            log_if_fail "send_join response", $response;

            Future->done;
         }),

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/join/$room_alias",

            content => {},
         )->main::expect_http_error()->then( sub {
            my ( $response ) = @_;

            # XXX currently synapse fails with a 500 here. I'm not really convinced that's
            # a thing we want to enforce, but we don't really have a specced way to say
            # "a remote server did something weird".
            Future->done(1);
         }),
      )
   };


test "Outbound federation rejects m.room.create events with an unknown room version",
   # we don't really require can_create_versioned_rooms, because the room is on the sytest server
   # but we use it as a proxy for "synapse supports room versioning"
   requires => [ local_user_fixture(), $main::INBOUND_SERVER,
                 federation_user_id_fixture(),
                 qw( can_create_versioned_room ) ],

   do => sub {
      my ( $user, $inbound_server, $creator_id ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $room_alias = "#no_create_event:$local_server_name";
      my $room = $datastore->create_room(
         creator => $creator_id,
         alias   => $room_alias,

         room_version => 'sytest-room-ver',
      );

      my $room_id = $room->room_id;

      Future->needs_all(
         $inbound_server->await_request_make_join( $room_id, $user->user_id )->then( sub {
            my ( $req, $room_id, $user_id ) = @_;

            my $proto = $room->make_join_protoevent(
               user_id => $user_id,
            );

            $proto->{origin}           = $inbound_server->server_name;
            $proto->{origin_server_ts} = $inbound_server->time_ms;

            $req->respond_json( {
               event => $proto,
            } );

            Future->done;
         }),

         $inbound_server->await_request_v2_send_join( $room_id )->then( sub {
            my ( $req, $room_id, $event_id ) = @_;

            $req->method eq "PUT" or
               die "Expected send_join method to be PUT";

            my $event = $req->body_from_json;
            log_if_fail "send_join event", $event;

            my @auth_chain = $datastore->get_auth_chain_events(
               @{ $room->event_ids_from_refs( $event->{auth_events} ) }
            );

            $req->respond_json(
               my $response = {
                  auth_chain => \@auth_chain,
                  state      => [ $room->current_state_events ],
               }
            );

            log_if_fail "send_join response", $response;

            Future->done;
         }),

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/join/$room_alias",

            content => {},
         )->main::expect_http_error()->then( sub {
            my ( $response ) = @_;

            # XXX currently synapse fails with a 500 here. I'm not really convinced that's
            # a thing we want to enforce, but we don't really have a specced way to say
            # "a remote server did something weird".
            Future->done(1);
         }),
      )
   };

test "Event with an invalid signature in the send_join response should not cause room join to fail",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER,
                 federation_user_id_fixture() ],

   do => sub {
      my ( $user, $inbound_server, $creator_id ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $room_alias = "#50fed-room-alias-invalid-sig:$local_server_name";
      my $room = $datastore->create_room(
         creator => $creator_id,
         alias   => $room_alias,
      );

      my $room_id = $room->room_id;

      my $event = $room->create_and_insert_event(
         sender      => "\@test:$local_server_name",
         type        => "test",
         room_id     => $room_id,
         state_key   => "",
         content     => {
            body    => "Test",
         },
      );

      # Modify the event (after the signature was generated) to invalidate the signature.
      $event->{origin} = "other-server:12345";

      my $await_request_send_join;

      $await_request_send_join = $inbound_server->await_request_v2_send_join( $room_id );

      Future->needs_all(
         $inbound_server->await_request_make_join( $room_id, $user->user_id )->then( sub {
            my ( $req, $room_id, $user_id ) = @_;

            my $proto = $room->make_join_protoevent(
               user_id => $user_id,
            );

            $proto->{origin}           = $inbound_server->server_name;
            $proto->{origin_server_ts} = $inbound_server->time_ms;

            $req->respond_json( {
               event => $proto,
            } );

            Future->done;
         }),

         $await_request_send_join->then( sub {
            my ( $req, $room_id, $event_id ) = @_;

            $req->method eq "PUT" or
               die "Expected send_join method to be PUT";

            my $event = $req->body_from_json;
            log_if_fail "send_join event", $event;

            my @auth_chain = $datastore->get_auth_chain_events(
               map { $_->[0] } @{ $event->{auth_events} }
            );

            my $response = {
               auth_chain => \@auth_chain,
               state      => [ $room->current_state_events ],
            };

            $req->respond_json($response);

            log_if_fail "send_join response", $response;

            Future->done;
         }),

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/join/$room_alias",

            content => {},
         )->then( sub {
            my ( $body ) = @_;
            log_if_fail "Join response", $body;

            assert_json_keys( $body, qw( room_id ));

            $body->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";

            matrix_get_my_member_event( $user, $room_id )
         })->then( sub {
            my ( $event ) = @_;

            assert_json_keys( $event->{content}, qw( membership ) );

            Future->done(1);
         }),
      )
   };

# A homeserver receiving a `send_join` request for a room version 6 room with
# a bad JSON value (e.g. a float) should reject the request.
#
# To test this we need to:
# * Send a successful `make_join` request.
# * Add a "bad" value into the returned prototype event.
# * Make a request to `send_join`.
# * Check that the response is M_BAD_JSON.
test "Inbound: send_join rejects invalid JSON for room version 6 rejects",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER,
                 local_user_and_room_fixtures( room_opts => { room_version => "6" } ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $creator->server_name;

      my $local_server_name = $outbound_client->server_name;
      my $datastore         = $inbound_server->datastore;

      $outbound_client->do_request_json(
         method   => "GET",
         hostname => $first_home_server,
         uri      => "/v1/make_join/$room_id/$user_id",
         params   => {
            ver => ["6"],
         },
      )->then( sub {
         my ( $body ) = @_;

         log_if_fail "make_join body", $body;

         my $protoevent = $body->{event};

         # It is assumed that the make_join response is sane, other tests ensure
         # this behavior.

         my %event = (
            ( map { $_ => $protoevent->{$_} } qw(
               auth_events content depth prev_events room_id sender
               state_key type ) ),

            origin           => $local_server_name,
            origin_server_ts => $inbound_server->time_ms,
         );
         # Insert a "bad" value into the send join, in this case a float.
         ${event}{content}{bad_val} = 1.1;

         $datastore->sign_event( \%event );

         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $first_home_server,
            uri      => "/v2/send_join/$room_id/xxx",
            content => \%event,
         )
      })->main::expect_m_bad_json;
   };
