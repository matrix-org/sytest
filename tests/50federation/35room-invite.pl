test "Outbound federation can send invites",
   requires => [ local_user_and_room_fixtures(), $main::INBOUND_SERVER, federation_user_id_fixture() ],

   do => sub {
      my ( $user, $room_id, $inbound_server, $invitee_id ) = @_;

      Future->needs_all(
         $inbound_server->await_request_invite( $room_id )->then( sub {
            my ( $req, undef ) = @_;

            assert_eq( $req->method, "PUT",
               'request method' );

            my $body = $req->body_from_json;
            log_if_fail "Invitation", $req->body_from_json;

            # this should be a member event
            assert_json_keys( $body, qw( event_id origin room_id sender type ));

            assert_eq( $body->{type}, "m.room.member",
               'event type' );
            assert_eq( $body->{origin}, $user->http->server_name,
               'event origin' );
            assert_eq( $body->{room_id}, $room_id,
               'event room_id' );
            assert_eq( $body->{sender}, $user->user_id,
               'event sender' );

            assert_json_keys( $body, qw( content state_key prev_state ));

            assert_deeply_eq( $body->{content}, { membership => "invite" },
               'event content' );
            assert_eq( $body->{state_key}, $invitee_id,
               'event state_key' );

            $inbound_server->datastore->sign_event( $body );

            $req->respond_json(
               # SYN-490
               [ 200 => { event => $body } ]
            );

            Future->done;
         }),

         matrix_invite_user_to_room( $user, $invitee_id, $room_id )
      );
   };

test "Inbound federation can receive invites",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER, $main::OUTBOUND_CLIENT,
                 federation_user_id_fixture() ],

   do => sub {
      my ( $user, $inbound_server, $outbound_client, $creator_id ) = @_;

      my $first_home_server = $user->http->server_name;

      my $datastore = $inbound_server->datastore;

      my $room = SyTest::Federation::Room->new(
         datastore => $datastore,
      );

      $room->create_initial_events(
         server  => $inbound_server,
         creator => $creator_id,
      );

      my $room_id = $room->room_id;

      my $invitation = $room->create_event(
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
            assert_deeply_eq( $event->{content}, { membership => "invite" },
               'event content' );

            Future->done(1);
         }),

         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $first_home_server,
            uri      => "/invite/$room_id/$invitation->{event_id}",

            content => $invitation,
         )->then( sub {
            my ( $response ) = @_;

            # $response seems to arrive with an extraneous layer of wrapping as
            # the result of a synapse implementation bug (SYN-490).
            if( ref $response eq "ARRAY" ) {
               $response->[0] == 200 or
                  die "Expected first response element to be 200";

               $response = $response->[1];
            }

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
   };
