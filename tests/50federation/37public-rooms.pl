use Future::Utils qw( try_repeat_until_success );


test "Inbound federation can get public room list",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],

   do => sub {
     my ( $outbound_client, $info, $creator, $room_id, $user_id ) = @_;
     my $first_home_server = $info->server_name;

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
         try_repeat_until_success( sub {
            $outbound_client->do_request_json(
               method   => "GET",
               hostname => $first_home_server,
               uri      => "/publicRooms",
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "Body", $body;

               assert_json_keys( $body, qw( chunk ) );

               any { $_->{room_id} eq $room_id } @{ $body->{chunk} }
                  or die "Room not in returned list";

               Future->done( 1 );
            })
         })
      });
   };
