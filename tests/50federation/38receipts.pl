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

         $event_id = $room->id_for_event( $event );

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


test "Inbound federation rejects receipts from wrong remote",
   requires => [ $main::OUTBOUND_CLIENT, $main::INBOUND_SERVER, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( room_opts => { room_version => "1" } ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $inbound_server, $info, $creator, $room_id, $user_id ) = @_;

      my $local_server_name = $info->server_name;
      my $remote_server_name = $inbound_server->server_name;

      my ( $event_id, );

      $outbound_client->join_room(
         server_name => $local_server_name,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         matrix_send_room_text_message( $creator, $room_id,
            body => "Test message1"
         )
      })->then( sub {
         ( $event_id ) = @_;

         # First we send a receipt from a user that isn't ours.
         $outbound_client->send_edu(
            edu_type    => "m.receipt",
            destination => $local_server_name,
            content     => {
               $room_id => {
                  "m.read" => {
                     $creator->user_id => {
                        event_ids => [ $event_id ],
                        data => { ts => 0 },
                     }
                  }
               }
            }
         );
      })->then( sub {
         # Then we send a receipt for a user that is ours.
         $outbound_client->send_edu(
            edu_type    => "m.receipt",
            destination => $local_server_name,
            content     => {
               $room_id => {
                  "m.read" => {
                     $user_id => {
                        event_ids => [ $event_id ],
                        data => { ts => 0 },
                     }
                  }
               }
            }
         );
      })->then( sub {
         # The sync should only contain the second receipt, since the first
         # should have been dropped.
         await_sync( $creator, check => sub {
            my ( $body ) = @_;

            sync_room_contains( $body, $room_id, "ephemeral", sub {
               my ( $receipt ) = @_;

               return unless $receipt->{type} eq "m.receipt";

               # Check for bad receipt
               defined $receipt->{content}{$event_id}{"m.read"}{ $creator->user_id }
                  and die "Found receipt that should have been rejected";

               # Stop waiting when we see the second receipt
               defined $receipt->{content}{$event_id}{"m.read"}{ $user_id };
            })
         })
      });
   };
