use Future::Utils qw( repeat );

test "Querying auth checks the events requested belong to the room",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],
   do => sub {
      my ( $outbound_client, $info, $priv_creator, $priv_room_id,
           $pub_creator, $pub_room_id, $fed_user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $priv_join_event;

      # Join the public room, but don't touch the private one
      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $pub_room_id,
         user_id     => $fed_user_id,
      )->then( sub {
         # Send an event into the private room
         matrix_send_room_text_message( $priv_creator, $priv_room_id,
            body => "Hello world",
         )
      })->then( sub {
         my ( $priv_event_id ) = @_;

         # We specifically use the public room, but the private event ID
         # That's the point of this test.
         $outbound_client->do_request_json(
            method   => "POST",
            hostname => $first_home_server,
            uri      => "/v1/query_auth/$pub_room_id/$priv_event_id",

            content => {
               auth_chain => [], # This is part of the exploit
            }
         )->main::expect_m_not_found;
      });
   };
