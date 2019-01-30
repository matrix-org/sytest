test "Server correctly handles transactions that break edu limits",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( user_opts => { with_events => 1 } ),
                 federation_user_id_fixture(), room_alias_name_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $creator_id, $room_alias_name ) = @_;

      my $local_server_name = $info->server_name;

      my $remote_server_name = $inbound_server->server_name;
      my $datastore          = $inbound_server->datastore;

      my $room_alias = "#$room_alias_name:$remote_server_name";

      my $device_id = "random_device_id";

      $outbound_client->join_room(
         server_name => $local_server_name,
         room_id     => $room_id,
         user_id     => $creator_id,
      )->then( sub {
         my ( $room ) = @_;

         my $new_event = $room->create_and_insert_event(
             type => "m.room.message",

             sender  => $creator_id,
             content => {
                 body => "Message 1",
             },
         );

         # Generate a messge with 51 PDUs
         my @pdus = ();
         for my $i ( 0 .. 50 ) {
             push @pdus, $new_event;
         }

         # Send the transaction to the client
         $outbound_client->send_transaction(
             pdus => \@pdus,
             destination => $local_server_name,
         )->main::expect_http_400();
      });
   };
