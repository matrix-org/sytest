test "Outbound federation can send events",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER ],

   do => sub {
      my ( $user, $inbound_server ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $creator = '@50fed:' . $local_server_name;
      my $room_alias = "#50fed-31send:$local_server_name";

      my $room = $datastore->create_room(
         creator => $creator,
         alias   => $room_alias,
      );

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/join/$room_alias",

         content => {},
      )->then( sub {
         my ( $body ) = @_;

         my $room_id = $body->{room_id};

         Future->needs_all(
            $inbound_server->await_event( "m.room.message", $room_id, sub {1} )
            ->then( sub {
               my ( $event ) = @_;
               log_if_fail "Received event", $event;

               assert_eq( $event->{sender}, $user->user_id,
                  'event sender' );
               assert_eq( $event->{content}{body}, "Hello",
                  'event content body' );

               Future->done(1);
            }),

            matrix_send_room_text_message( $user, $room_id, body => "Hello" ),
         );
      });
   };
