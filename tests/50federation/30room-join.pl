use List::UtilsBy qw( partition_by );

multi_test "Inbound federation can receive room-join requests",
   requires => [qw( outbound_client inbound_server first_home_server ),
                 room_fixture( requires_users => [ local_user_fixture() ] ) ],

   do => sub {
      my ( $outbound_client, $inbound_server, $first_home_server, $room_id ) = @_;

      my $local_server_name = $outbound_client->server_name;

      my $user_id = "\@50fed-user:$local_server_name";

      $outbound_client->do_request_json(
         method => "GET",
         uri    => "/make_join/$room_id/$user_id",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "make_join body", $body;

         # TODO(paul): This is all entirely cargoculted guesswork based on
         #   observing what Synapse actually does, because the entire make_join
         #   API is entirely undocumented. See SPEC-241

         require_json_keys( $body, qw( event ));

         my $protoevent = $body->{event};

         require_json_keys( $protoevent, qw(
            auth_events content depth event_id prev_state room_id sender state_key type
         ));

         require_json_nonempty_list( my $auth_events = $protoevent->{auth_events} );
         foreach my $auth_event ( @$auth_events ) {
            require_json_list( $auth_event );
            @$auth_event == 2 or
               die "Expected auth_event list element to have 2 members";

            require_json_string( $auth_event->[0] );  # id
            require_json_object( $auth_event->[1] );  # hashes
         }

         require_json_nonempty_list( $protoevent->{prev_events} );

         require_json_number( $protoevent->{depth} );
         require_json_string( $protoevent->{event_id} );

         $protoevent->{room_id} eq $room_id or
            die "Expected 'room_id' to be $room_id";
         $protoevent->{sender} eq $user_id or
            die "Expected 'sender' to be $user_id";
         $protoevent->{state_key} eq $user_id or
            die "Expected 'state_key' to be $user_id";
         $protoevent->{type} eq "m.room.member" or
            die "Expected 'type' to be 'm.room.member'";

         require_json_keys( my $content = $protoevent->{content}, qw( membership ) );
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

         # TODO: hashes

         # TODO: should now sign the event

         $outbound_client->do_request_json(
            method => "PUT",
            uri    => "/send_join/$room_id/$event{event_id}",

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

         require_json_keys( $response, qw( auth_chain state ));

         require_json_nonempty_list( $response->{auth_chain} );
         my @auth_chain = @{ $response->{auth_chain} };

         log_if_fail "Auth chain", \@auth_chain;

         foreach my $event ( @auth_chain ) {
            require_json_keys( $event, qw(
               auth_events content depth event_id hashes origin origin_server_ts
               prev_events prev_state room_id sender signatures state_key type
            ));

            require_json_list( $event->{auth_events} );
            require_json_number( $event->{depth} );
            require_json_string( $event->{event_id} );
            require_json_object( $event->{hashes} );

            require_json_string( $event->{origin} );

            require_json_number( $event->{origin_server_ts} );
            require_json_list( $event->{prev_events} );
            require_json_list( $event->{prev_state} );

            require_json_string( $event->{room_id} );
            $event->{room_id} eq $room_id or
               die "Expected auth_event room_id to be $room_id";

            require_json_string( $event->{sender} );
            require_json_object( $event->{signatures} );
            require_json_string( $event->{state_key} );
            require_json_string( $event->{type} );

            # TODO: Check signatures of every auth event
         }

         # TODO: Perform some linkage checking between the auth events

         require_json_nonempty_list( $response->{state} );
         my %state = partition_by { $_->{type} } @{ $response->{state} };

         log_if_fail "State", \%state;

         # TODO: lots more checking. Requires spec though
         Future->done(1);
      });
   };
