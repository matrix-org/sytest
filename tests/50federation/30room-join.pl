use List::UtilsBy qw( partition_by extract_by );

sub make_auth_events
{
   [ map { [ $_->{event_id}, $_->{hashes} ] } @_ ];
}

test "Outbound federation can send room-join requests",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER ],

   do => sub {
      my ( $user, $inbound_server ) = @_;
      my $local_server_name = $inbound_server->server_name;

      # We'll have to jump through the extra hoop of using the directory
      # service first, because we can't join a remote room by room ID alone

      my $room_alias = "#50fed-room-alias:$local_server_name";
      my $room_id    = "!50fed-room-alias:$local_server_name";
      my $creator    = '@50fed:' . $local_server_name;

      require_stub $inbound_server->await_query_directory( $room_alias )
         ->on_done( sub {
            my ( $req ) = @_;

            $req->respond_json( {
               room_id => $room_id,
               servers => [
                  $local_server_name,
               ]
            } );
         });

      my $create_event = $inbound_server->create_event(
         type => "m.room.create",

         auth_events => [],
         prev_events => [],
         prev_state  => [],
         content     => { creator => $creator },
         depth       => 0,
         room_id     => $room_id,
         sender      => $creator,
         state_key   => "",
      );

      my $joinrules_event = $inbound_server->create_event(
         type => "m.room.join_rules",

         auth_events => make_auth_events( $create_event ),
         prev_events => make_auth_events( $create_event ),
         prev_state  => [],
         content     => { join_rule => "public" },
         depth       => 0,
         room_id     => $room_id,
         sender      => $creator,
         state_key   => "",
      );

      my %join_protoevent = (
         type => "m.room.member",

         auth_events      => make_auth_events( $create_event, $joinrules_event ),
         content          => { membership => "join" },
         depth            => 0,
         event_id         => my $join_event_id = $inbound_server->next_event_id,
         origin           => $inbound_server->server_name,
         origin_server_ts => $inbound_server->time_ms,
         prev_events      => [],
         room_id          => $room_id,
         sender           => $user->user_id,
         state_key        => $user->user_id,
      );

      Future->needs_all(
         # Await PDU?

         $inbound_server->await_make_join( $room_id, $user->user_id )->then( sub {
            my ( $req, $room_id, $user_id ) = @_;

            $req->respond_json( {
               event => \%join_protoevent,
            } );

            Future->done;
         }),

         $inbound_server->await_send_join( $room_id, $join_event_id )->then( sub {
            my ( $req, $room_id, $event_id ) = @_;

            $req->method eq "PUT" or
               die "Expected send_join method to be PUT";

            my $event = $req->body_from_json;
            log_if_fail "send_join event", $event;

            my @auth_chain = map {
               $inbound_server->get_event( $_->[0] )
            } @{ $event->{auth_events} };

            $req->respond_json(
               # TODO(paul): This workaround is for SYN-490
               [ 200, {
                  auth_chain => \@auth_chain,
                  state      => [],
               } ]
            );

            Future->done;
         }),

         do_request_json_for( $user,
            method => "POST",
            uri    => "/api/v1/join/$room_alias",

            content => {},
         )->then( sub {
            my ( $body ) = @_;
            log_if_fail "Join response", $body;

            assert_json_keys( $body, qw( room_id ));

            $body->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";

            Future->done(1);
         }),
      )
   };

test "Inbound federation can receive room-join requests",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER,
                 $main::HOMESERVER_INFO[0],
                 room_fixture( requires_users => [ local_user_fixture() ] ) ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $room_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $user_id = "\@50fed-user:$local_server_name";

      $outbound_client->do_request_json(
         method   => "GET",
         hostname => $first_home_server,
         uri      => "/make_join/$room_id/$user_id",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "make_join body", $body;

         # TODO(paul): This is all entirely cargoculted guesswork based on
         #   observing what Synapse actually does, because the entire make_join
         #   API is entirely undocumented. See SPEC-241

         assert_json_keys( $body, qw( event ));

         my $protoevent = $body->{event};

         assert_json_keys( $protoevent, qw(
            auth_events content depth event_id prev_state room_id sender state_key type
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
         assert_json_string( $protoevent->{event_id} );

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
               auth_events content depth prev_events prev_state room_id sender
               state_key type ) ),

            event_id         => $inbound_server->next_event_id,
            origin           => $local_server_name,
            origin_server_ts => $inbound_server->time_ms,
         );

         $outbound_client->do_request_json(
            method   => "PUT",
            hostname => $first_home_server,
            uri      => "/send_join/$room_id/$event{event_id}",

            content => \%event,
         )
      })->then( sub {
         my ( $response ) = @_;

         # $response seems to arrive with an extraneous layer of wrapping as
         # the result of a synapse implementation bug (SYN-490).
         if( ref $response eq "ARRAY" ) {
            $response->[0] == 200 or
               die "Expected first response element to be 200";

            warn "SYN-490 detected; deploying workaround\n";
            $response = $response->[1];
         }

         assert_json_keys( $response, qw( auth_chain state ));

         assert_json_nonempty_list( $response->{auth_chain} );
         my @auth_chain = @{ $response->{auth_chain} };

         log_if_fail "Auth chain", \@auth_chain;

         foreach my $event ( @auth_chain ) {
            assert_json_keys( $event, qw(
               auth_events content depth event_id hashes origin origin_server_ts
               prev_events prev_state room_id sender signatures state_key type
            ));

            assert_json_list( $event->{auth_events} );
            assert_json_number( $event->{depth} );
            assert_json_string( $event->{event_id} );
            assert_json_object( $event->{hashes} );

            assert_json_string( $event->{origin} );

            assert_json_number( $event->{origin_server_ts} );
            assert_json_list( $event->{prev_events} );
            assert_json_list( $event->{prev_state} );

            assert_json_string( $event->{room_id} );
            $event->{room_id} eq $room_id or
               die "Expected auth_event room_id to be $room_id";

            assert_json_string( $event->{sender} );
            assert_json_object( $event->{signatures} );
            assert_json_string( $event->{state_key} );
            assert_json_string( $event->{type} );

            # TODO: Check signatures of every auth event
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
