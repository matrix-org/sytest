test "Server correctly handles transactions that break edu limits",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $creator, $room_id, $user_id ) = @_;

      $outbound_client->join_room(
         server_name => $creator->server_name,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         my ( $room ) = @_;

         my $new_event = $room->create_and_insert_event(
             type => "m.room.message",

             sender  => $user_id,
             content => {
                 body => "Message 1",
             },
         );

         # Generate two transactions, one that breaks the 50 PDU limit and one
         # that does not
         my @bad_pdus = ( $new_event ) x 51;
         my @good_pdus = ( $new_event ) x 10;

         Future->needs_all(
            # Send the transaction to the client and expect a fail
            $outbound_client->send_transaction(
                pdus => \@bad_pdus,
                destination => $creator->server_name,
            )->main::expect_http_400(),

            # Send the transaction to the client and expect a succeed
            $outbound_client->send_transaction(
                pdus => \@good_pdus,
                destination => $creator->server_name,
            )->then( sub {
                my ( $response ) = @_;

                Future->done( 1 );
            }),
         );
      });
   };

# Room version 6 states that homeservers should strictly enforce canonical JSON
# on PDUs. Test that a transaction to `send` with a PDU that has bad data will
# be handled properly.
#
# This enforces that invalid PDUs are discarded rather than failing the entire
# transaction.
#
# See https://github.com/matrix-org/synapse/issues/7543
test "Server discards events with invalid JSON in a version 6 room",
   requires => [ $main::OUTBOUND_CLIENT,
                 federated_rooms_fixture( room_opts => { room_version => "6" } ) ],
   # This behaviour has only been changed in Synapse, not Dendrite
   implementation_specific => ['synapse'],

   do => sub {
      my ( $outbound_client, $creator, $user_id, @rooms ) = @_;

      my $room = $rooms[0];
      my $room_id = $room->room_id;

      my $good_event = $room->create_and_insert_event(
          type => "m.room.message",

          sender  => $user_id,
          content => {
              body    => "Good event",
          },
      );

      my $bad_event = $room->create_and_insert_event(
          type => "m.room.message",

          sender  => $user_id,
          content => {
             body    => "Bad event",
             # Insert a "bad" value into the PDU, in this case a float.
             bad_val => 1.1,
          },
      );

      my @pdus = ( $good_event, $bad_event );

      # Send the transaction to the client and expect to succeed
      $outbound_client->send_transaction(
          pdus => \@pdus,
          destination => $creator->server_name,
      )->then(sub {
         # Wait for the good event to be sent down through sync
         await_sync_timeline_contains( $creator, $room_id, check => sub {
            my ( $event ) = @_;
            $event->{type} eq "m.room.message" &&
               $event->{content}{body} eq "Good event"
         })
      })->then(sub {
         # Check that we can fetch the good event
         my $event_id = $room->id_for_event( $good_event );
         do_request_json_for( $creator,
             method  => "GET",
             uri     => "/v3/rooms/$room_id/event/$event_id",
         )
      })->then(sub {
         # Check that we have ignored the bad event PDU
         my $event_id = $room->id_for_event( $bad_event );
         do_request_json_for( $creator,
             method  => "GET",
             uri     => "/v3/rooms/$room_id/event/$event_id",
         )->main::expect_m_not_found
      });
   };

# This is an alternative behaviour that isn't spec compliant, where the server
# rejects the whole transaction if any PDU is invalid.
# This is the behaviour that Dendrite currently implements.
test "Server rejects invalid JSON in a version 6 room",
   requires => [ $main::OUTBOUND_CLIENT,
                 federated_rooms_fixture( room_opts => { room_version => "6" } ) ],
   implementation_specific => ['dendrite'],

   do => sub {
      my ( $outbound_client, $creator, $user_id, @rooms ) = @_;

      my $room = $rooms[0];
      my $room_id = $room->room_id;

      my $good_event = $room->create_and_insert_event(
          type => "m.room.message",

          sender  => $user_id,
          content => {
              body    => "Good event",
          },
      );

      my $bad_event = $room->create_and_insert_event(
          type => "m.room.message",

          sender  => $user_id,
          content => {
             body    => "Bad event",
             # Insert a "bad" value into the PDU, in this case a float.
             bad_val => 1.1,
          },
      );

      my @pdus = ( $good_event, $bad_event );

      # Send the transaction to the client and expect to fail
      $outbound_client->send_transaction(
          pdus => \@pdus,
          destination => $creator->server_name,
      )->main::expect_bad_json
   };
