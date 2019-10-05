test "Inbound federation can get public room list",
   requires => [ $main::OUTBOUND_CLIENT,
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],

   do => sub {
     my ( $outbound_client, $creator, $room_id, $user_id ) = @_;
     my $first_home_server = $creator->server_name;

     my $local_server_name = $outbound_client->server_name;

     my $room;

     $outbound_client->join_room(
        server_name => $first_home_server,
        room_id     => $room_id,
        user_id     => $user_id,
     )->then( sub {
        ( $room ) = @_;

        do_request_json_for( $creator,
           method   => "PUT",
           uri      => "/r0/directory/list/room/$room_id",
           content  => {
             visibility => "public",
          },
        );
      })->then( sub {
         repeat_until_true {
            $outbound_client->do_request_json(
               method   => "GET",
               hostname => $first_home_server,
               uri      => "/v1/publicRooms",
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "Body", $body;

               assert_json_keys( $body, qw( chunk ) );

               Future->done( any { $_->{room_id} eq $room_id } @{ $body->{chunk} } );
            })
         };
      });
   };
