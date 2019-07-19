test "Server correctly handles transactions that break edu limits",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( room_opts => { room_version => "1" } ),
                 room_alias_name_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $room_alias_name ) = @_;

      my $local_server_name = $info->server_name;

      my $remote_server_name = $inbound_server->server_name;

      my $room_alias = "#$room_alias_name:$remote_server_name";

      $outbound_client->join_room(
         server_name => $local_server_name,
         room_id     => $room_id,
         user_id     => $creator->user_id,
      )->then( sub {
         my ( $room ) = @_;

         my $new_event = $room->create_and_insert_event(
             type => "m.room.message",

             sender  => $creator->user_id,
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
                destination => $local_server_name,
            )->main::expect_http_400(),

            # Send the transaction to the client and expect a succeed
            $outbound_client->send_transaction(
                pdus => \@good_pdus,
                destination => $local_server_name,
            )->then( sub {
                my ( $response ) = @_;

                Future->done( 1 );
            }),
         );
      });
   };
