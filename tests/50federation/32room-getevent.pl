test "Inbound federation can return events",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $info, undef, $room_id, $user_id ) = @_;
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
            uri      => "/v1/event/$member_event->{event_id}/",
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


test "Inbound federation redacts events from erased users",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures(),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $message_id;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         my ( $room ) = @_;

         # have the creator send a message into the room, which we will try to
         # fetch.
         matrix_send_room_text_message( $creator, $room_id, body => "body1" );
      })->then( sub {
         ( $message_id ) = @_;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/event/$message_id/",
         );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Fetched event before erasure", $body;

         assert_json_keys( $body, qw( origin origin_server_ts pdus ));
         assert_json_list( my $events = $body->{pdus} );

         @$events == 1 or
            die "Expected 1 event, found " . scalar(@$events);
         my ( $event ) = @$events;

         # Check that the content is right
         assert_eq( $event->{content}->{body}, "body1" );

         # now do the erasure
         matrix_deactivate_account( $creator, erase => JSON::true );
      })->then( sub {
         # re-fetch the event and check that it is redacted.
         retry_until_success {
            $outbound_client->do_request_json(
               method   => "GET",
               hostname => $first_home_server,
               uri      => "/v1/event/$message_id/",
            )->then( sub {
               my ( $body ) = @_;
               log_if_fail "Fetched event after erasure", $body;

               assert_json_keys( $body, qw( origin origin_server_ts pdus ));
               assert_json_list( my $events = $body->{pdus} );

               @$events == 1 or
                  die "Expected 1 event, found " . scalar(@$events);
               my ( $event ) = @$events;

               # Check that the content has been redacted
               exists $event->{content}->{body} and
                  die "Event was not redacted";

               Future->done(1);
            })
         }
      });
   };

