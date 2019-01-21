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

            assert_eq( $body->{content}{membership}, "invite",
               'event content membership' );
            assert_eq( $body->{state_key}, $invitee_id,
               'event state_key' );

            $inbound_server->datastore->sign_event( $body );

            $req->respond_json(
               # SYN-490
               [ 200, { event => $body } ]
            );

            Future->done;
         }),

         matrix_invite_user_to_room( $user, $invitee_id, $room_id )
      );
   };

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
         $room, $user, $inbound_server, $invitation,
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

   do_v1_invite_request( $room, $user, $inbound_server, $invitation )

Send an invite event via the V1 API

=cut

sub do_v1_invite_request
{
   my ( $room, $user, $inbound_server, $invitation ) = @_;

   my $outbound_client = $inbound_server->client;
   my $first_home_server = $user->http->server_name;
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

   do_v2_invite_request( $room, $user, $inbound_server, $invitation )

Send an invite event via the V2 API

=cut

sub do_v2_invite_request
{
   my ( $room, $user, $inbound_server, $invitation ) = @_;

   my $outbound_client = $inbound_server->client;
   my $first_home_server = $user->http->server_name;
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
         create_federation_server()
      },
      teardown => sub {
         my ($server) = @_;
         $server->close();
      }
   );

   test "Inbound federation can receive invite and reject when "
         . ( $error_code >= 0 ? "remote replies with a $error_code" :
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
               $federation_server->close();

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
