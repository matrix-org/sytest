# in order to check that each endpoint is subject to the server_acls list, we
# define a test routine for each endpoint.
#
# We then run a separate test for each endpoint, each of which:
#  * creates a room on synapse
#  * checks that the operation works as normal before a ban
#  * applies a ban
#  * checks that the operation is now blocked.
#
# The test routines are called with a number of useful parameters; the most
# important is 'expect_ban', which tells it whether the ban is in place yet,
# and hence whether it should be expecting success or failure.
#
# Obviously, to best ensure that we are testing what we think we are testing,
# the test routines should behave as similarly as they can for the expect_ban
# case and the control case.

my @TESTS = (
   [ "send events", *can_send_event ],
   [ "/make_join",  *can_make_join ],
   [ "/send_join", *can_send_join ],
   [ "/make_leave",  *can_make_leave ],
   [ "/send_leave",  *can_send_leave ],
   [ "/invite",  *can_invite ],
   [ "get room state", *can_get_state ],
   [ "get room state ids", *can_get_state_ids ],
   [ "backfill", *can_backfill ],
   [ "/event_auth", *can_event_auth ],
   [ "query auth", *can_query_auth ],
   [ "get missing events", *can_get_missing_events ],
);

sub can_send_event {
   my ( %params ) = @_;

   my ($event, $event_id) = $params{room}->create_event(
      type => "m.room.message",

      sender  => $params{sytest_user_id},
      content => {
         body => "Hello",
      },
   );

   $params{outbound_client}->send_transaction(
      pdus => [ $event ],
      destination => $params{dest_server},
   )->then( sub {
      my ( $body ) = @_;
      log_if_fail "/send/ response", $body;

      my $pdu_result = $body->{pdus}->{$event_id};

      if( $params{expect_ban} ) {
         assert_json_keys( $pdu_result, qw( errcode ));
         assert_eq( $pdu_result->{errcode}, 'M_FORBIDDEN',
                    "error code for forbidden /send" );
      } else {
         assert_deeply_eq( $pdu_result, {}, "result for permitted /send" );
      }
      Future->done(1);
   });
}

sub can_make_join {
   my ( %params ) = @_;
   my $room_id = $params{room}->{room_id};
   my $sytest_user_id = $params{sytest_user_id};

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "GET",
         hostname => $params{dest_server},
         uri      => "/v1/make_join/$room_id/$sytest_user_id",
         params   => { "ver" => [1, 2, 3, 4, 5] },
      ), $params{expect_ban}, "/make_join",
   );
}

sub can_make_leave {
   my ( %params ) = @_;
   my $room_id = $params{room}->{room_id};
   my $sytest_user_id = $params{sytest_user_id};

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "GET",
         hostname => $params{dest_server},
         uri      => "/v1/make_leave/$room_id/$sytest_user_id"
      ), $params{expect_ban}, "/make_leave",
   );
}

sub can_send_join {
   my ( %params ) = @_;
   my $room_id = $params{room}->{room_id};
   my $sytest_user_id = $params{sytest_user_id};

   my ($join_event, $event_id)  = $params{room}->create_event(
      type      => "m.room.member",
      sender    => $sytest_user_id,
      state_key => $sytest_user_id,
      content   => {
         membership => "join",
      },
   );

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "PUT",
         hostname => $params{dest_server},
         uri      => "/v1/send_join/$room_id/$event_id",
         content  => $join_event,
      ), $params{expect_ban}, "/send_join",
   );
}

sub can_send_leave {
   my ( %params ) = @_;
   my $room_id = $params{room}->{room_id};
   my $sytest_user_id = $params{sytest_user_id};

   my ($leave_event, $event_id) = $params{room}->create_event(
      type      => "m.room.member",
      sender    => $sytest_user_id,
      state_key => $sytest_user_id,
      content   => {
         membership => "leave",
      },
   );

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "PUT",
         hostname => $params{dest_server},
         uri      => "/v1/send_leave/$room_id/$event_id",
         content  => $leave_event,
      ), $params{expect_ban}, "/send_leave",
   );
}

sub can_invite {
   my ( %params ) = @_;
   my $room_id = $params{room}->{room_id};
   my $sytest_user_id = $params{sytest_user_id};
   my $dest_server = $params{dest_server};
   my $invited_user = '@serveracls-invited_user:'.$dest_server;

   my ($invitation, $event_id) = $params{room}->create_event(
     type => "m.room.member",

     content   => { membership => "invite" },
     sender    => $sytest_user_id,
     state_key => $invited_user,
   );

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "PUT",
         hostname => $params{dest_server},
         uri      => "/v2/invite/$room_id/$event_id",
         content  => {
            event => $invitation,
            room_version => $params{room}->{room_version},
            invite_room_state => [],
         },
      ), $params{expect_ban}, "/invite",
   );
}

sub can_get_state {
   my ( %params ) = @_;
   my $room = $params{room};
   my $room_id = $room->{room_id};
   my $event_id = $room->id_for_event($room->{prev_events}[-1]);

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "GET",
         hostname => $params{dest_server},
         uri      => "/v1/state/$room_id",
         params   => {
            event_id => $event_id,
         },
      ), $params{expect_ban}, "/state",
   );
}

sub can_get_state_ids {
   my ( %params ) = @_;
   my $room = $params{room};
   my $room_id = $room->{room_id};
   my $event_id = $room->id_for_event($room->{prev_events}[-1]);

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "GET",
         hostname => $params{dest_server},
         uri      => "/v1/state_ids/$room_id/",
         params   => {
            event_id => $event_id,
         },
      ), $params{expect_ban}, "/state_ids",
   );
}

sub can_backfill {
   my ( %params ) = @_;
   my $room = $params{room};
   my $room_id = $room->{room_id};
   my $event_id = $room->id_for_event($room->{prev_events}[-1]);

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "GET",
         hostname => $params{dest_server},
         uri      => "/v1/backfill/$room_id/",
         params   => {
            v => $event_id,
            limit => 100,
         },
      ), $params{expect_ban}, "/backfill",
   );
}

sub can_event_auth {
   my ( %params ) = @_;
   my $room = $params{room};
   my $room_id = $room->{room_id};
   my $event_id = $room->id_for_event($room->{prev_events}[-1]);

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "GET",
         hostname => $params{dest_server},
         uri      => "/v1/event_auth/$room_id/$event_id",
      ), $params{expect_ban}, "/event_auth",
   );
}

sub can_query_auth {
   my ( %params ) = @_;
   my $room = $params{room};
   my $room_id = $room->{room_id};
   my $event_id = $room->id_for_event($room->{prev_events}[-1]);

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "POST",
         hostname => $params{dest_server},
         uri      => "/v1/query_auth/$room_id/$event_id",
         content  => {
            auth_chain => [],
         },
      ), $params{expect_ban}, "/query_auth",
   );
}

sub can_get_missing_events {
   my ( %params ) = @_;
   my $room = $params{room};
   my $room_id = $room->{room_id};

   maybe_expect_forbidden(
      $params{outbound_client}->do_request_json(
         method   => "POST",
         hostname => $params{dest_server},
         uri      => "/v1/get_missing_events/$room_id",
         content  => {}
      ), $params{expect_ban}, "/get_missing_events",
   );
}


foreach my $t ( @TESTS ) {
   my( $desc, $check, %params ) = @$t;
   my $extra_requires = $params{extra_requires} // [];

   test "Banned servers cannot $desc",
      requires => [ $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                    local_user_and_room_fixtures(),
                    federation_user_id_fixture(),
                    @$extra_requires,
                  ],
      do => sub {
         my ( $inbound_server, $info, $creator, $room_id,
              $sytest_user_id, @extra_fixtures) = @_;

         my $outbound_client = $inbound_server->client;
         my $first_home_server = $info->server_name;

         # strip off the port from the server name for the ACL rules.
         my ( $local_server_name ) = (
            $outbound_client->server_name =~ /^(.*):[0-9]+$/
         );
         my %check_params = (
            synapse_hs_info => $info,
            synapse_user    => $creator,
            sytest_user_id  => $sytest_user_id,
            dest_server     => $first_home_server,
            outbound_client => $outbound_client,
            fixtures        => \@extra_fixtures,
         );

         $outbound_client->join_room(
            server_name => $first_home_server,
            room_id     => $room_id,
            user_id     => $sytest_user_id,
         )->then( sub {
            my ( $room ) = @_;
            $check_params{room} = $room;

            # check that we are not yet banned
            $check->( expect_ban => 0, %check_params );
         })->then( sub {
            # ban the server
            $inbound_server->await_event( "m.room.server_acl", $room_id, sub {1} );
            matrix_put_room_state_synced(
               $creator, $room_id,
               type => "m.room.server_acl",
               content => {
                  deny => [ $local_server_name ],
                  allow => [ "*" ],
               },
            );
         })->then( sub {
            $check->( expect_ban => 1, %check_params );
         });
    };
}

# expect an M_FORBIDDEN response if $expect_forbidden is set, else expect a 200
sub maybe_expect_forbidden {
   my( $f, $expect_forbidden, $msg ) = @_;

   if( $expect_forbidden ) {
      return expect_forbidden($f, "forbidden $msg");
   }

   return $f->then( sub {
      my ( $body ) = @_;
      log_if_fail "allowed $msg response", $body;
      Future->done(1);
   });
}

# expect an http request to fail with an M_FORBIDDEN error code
sub expect_forbidden {
   my( $f, $msg ) = @_;

   $f->main::expect_http_403()->then( sub {
     my ( $resp ) = @_;
     my $body = JSON::decode_json $resp->content;
     log_if_fail "$msg response", $body;

     assert_json_keys( $body, qw( errcode ));
     my $errcode = $body->{errcode};
     assert_eq( $errcode, 'M_FORBIDDEN', "$msg errcode");
     Future->done(1);
  });
}

