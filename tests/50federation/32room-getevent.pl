test "Inbound federation can return events",
   requires => [
      $main::OUTBOUND_CLIENT,
      federated_rooms_fixture(),
   ],

   do => sub {
      my ( $outbound_client, $creator, $user_id, $room ) = @_;
      my $first_home_server = $creator->server_name;

      my $member_event = $room->get_current_state_event( "m.room.member", $user_id );
      log_if_fail "Member event", $member_event;

      my $event_id = $room->id_for_event( $member_event );

      $outbound_client->do_request_json(
         method   => "GET",
         hostname => $first_home_server,
         uri      => "/v1/event/$event_id",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( origin origin_server_ts pdus ));
         assert_json_list( my $events = $body->{pdus} );

         @$events == 1 or
            die "Expected 1 event, found " . scalar(@$events);
         my ( $event ) = @$events;

         # Check that the string fields seem right
         assert_eq( $event->{$_}, $member_event->{$_},
            "event $_" ) for qw( depth origin room_id sender state_key type );

         if ( $room->room_version eq "1" || $room->room_version eq "2" ) {
            assert_eq( $event->{event_id}, $member_event->{event_id}, "event_id" );
         }

         Future->done(1);
      });
   };


test "Inbound federation redacts events from erased users",
   requires => [
      $main::OUTBOUND_CLIENT,
      federated_rooms_fixture(),
   ],

   do => sub {
      my ( $outbound_client, $creator, $user_id, $room ) = @_;
      my $first_home_server = $creator->server_name;
      my $room_id = $room->room_id;

      my $message_id;

      # have the creator send a message into the room, which we will try to
      # fetch.
      matrix_send_room_text_message( $creator, $room_id, body => "body1" )
      ->then( sub {
         ( $message_id ) = @_;

         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/event/$message_id",
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
               uri      => "/v1/event/$message_id",
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
