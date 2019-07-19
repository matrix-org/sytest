test "Outbound federation sends receipts",
   requires => [ local_user_and_room_fixtures( room_opts => { room_version => "1" } ),
                 federation_user_id_fixture(),
                 $main::OUTBOUND_CLIENT,
                 $main::INBOUND_SERVER,
                 $main::HOMESERVER_INFO[0],
                 qw( can_post_room_receipts ),
               ],
   do => sub {
      my ( $creator_user, $room_id, $federated_user_id, $outbound_client, $inbound_server, $server_0 ) = @_;

      my $event_id;

      $outbound_client->join_room(
         server_name => $server_0->server_name,
         room_id     => $room_id,
         user_id     => $federated_user_id,
      )->then( sub {
         # send a message from the federated user
         my ( $room ) = @_;

         my $event = $room->create_and_insert_event(
            type => "m.room.message",

            sender  => $federated_user_id,
            content => {
               body => "Hello",
            },
         );

         $event_id = $event->{event_id};

         $outbound_client->send_event(
            event => $event,
            destination => $server_0->server_name,
         );
      })->then( sub {
         await_sync_timeline_contains( $creator_user, $room_id, check => sub {
            return $_[0]->{event_id} eq $event_id;
         });
      })->then( sub {
         # send a RR from the creator
         Future->needs_all(
            matrix_advance_room_receipt( $creator_user, $room_id, 'm.read', $event_id),
            $inbound_server->await_edu( "m.receipt", sub {1} )->then( sub {
               my ( $edu ) = @_;
               # {
               #    edu_type => "m.receipt",
               #    content  => {
               #                 "!ZoCchUjicQWJNBYbKs:localhost:8800" => {
               #                   "m.read" => {
               #                     "\@anon-20190313_122311-1:localhost:8800" => {
               #                       data => { ts => 1552479794711 },
               #                       event_ids => ["\$1:localhost:39803"],
               #                     },
               #                   },
               #                 },
               #               },
               # }

               log_if_fail "Received edu", $edu;
               my $rr = $edu->{content}{$room_id}{"m.read"}{$creator_user->user_id};
               die "Didn't find RR" unless $rr;
               assert_json_keys( $rr, qw( data event_ids ));
               assert_json_keys( $rr->{data}, qw( ts ));
               assert_deeply_eq( $rr->{event_ids}, [ $event_id ] );
               Future->done(1);
            }),
         );
      });
   };
