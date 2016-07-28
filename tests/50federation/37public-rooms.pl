test "Inbound federation can get state for a room",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0] ],

   do => sub {
      my ( $outbound_client, $info ) = @_;
      my $first_home_server = $info->server_name;

      $outbound_client->do_request_json(
         method   => "GET",
         hostname => $first_home_server,
         uri      => "/publicRooms",
      );
   };
