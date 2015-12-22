test "Inbound federation can return events",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 room_fixture( requires_users => [ local_user_fixture() ] ),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $info, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      my $member_event;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         my ( $room ) = @_;

         $member_event = $room->get_current_state_event( "m.room.member", $user_id );
         log_if_fail "Member event", $member_event;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/event/$member_event->{event_id}/",
         );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( origin origin_server_ts pdus ));
         assert_json_list( my $events = $body->{pdus} );

         @$events == 1 or
            die "Expected 1 event, found " . scalar(@$events);
         my ( $event ) = @$events;

         # Check that the string fields seem right
         assert_eq( $event->{$_}, $member_event->{$_},
            "event $_" ) for qw( depth event_id origin room_id sender state_key type );

         Future->done(1);
      });
   };

