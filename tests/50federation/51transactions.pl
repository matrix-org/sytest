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

# This currently tests that the entire transaction is rejected if a single bad
# PDU is sent in. It is unclear if this is the correct behavior or not.
#
# See https://github.com/matrix-org/synapse/issues/7543
test "Server rejects invalid JSON in a version 6 room",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_and_room_fixtures( room_opts => { room_version => "6" } ),
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
                body    => "Message 1",
                bad_val => 1.1,
             },
         );

         my @pdus = ( $new_event );

         # Send the transaction to the client and expect a fail
         $outbound_client->send_transaction(
             pdus => \@pdus,
             destination => $creator->server_name,
         )->main::expect_m_bad_json;
      });
   };
