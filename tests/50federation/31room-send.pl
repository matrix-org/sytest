use Protocol::Matrix qw( redact_event );

test "Outbound federation can send events",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER, federation_user_id_fixture() ],

   do => sub {
      my ( $user, $inbound_server, $creator_id ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $room_alias = "#50fed-31send:$local_server_name";

      my $room = $datastore->create_room(
         creator => $creator_id,
         alias   => $room_alias,
      );

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/join/$room_alias",

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

test "Inbound federation can receive events",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( user_opts => { with_events => 1 }),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         my ( $room ) = @_;

         my $event = $room->create_and_insert_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Hello",
            },
         );

         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         );
      })->then( sub {
         await_event_for( $creator, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{room_id} eq $room_id;

            assert_eq( $event->{sender}, $user_id,
               'event sender' );
            assert_eq( $event->{content}{body}, "Hello",
               'event content body' );

            Future->done(1);
         });
      });
   };

test "Inbound federation can receive redacted events",
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_and_room_fixtures( user_opts => { with_events => 1 }),
                 federation_user_id_fixture() ],

   do => sub {
      my ( $outbound_client, $info, $creator, $room_id, $user_id ) = @_;
      my $first_home_server = $info->server_name;

      my $local_server_name = $outbound_client->server_name;

      $outbound_client->join_room(
         server_name => $first_home_server,
         room_id     => $room_id,
         user_id     => $user_id,
      )->then( sub {
         my ( $room ) = @_;

         my $event = $room->create_and_insert_event(
            type => "m.room.message",

            sender  => $user_id,
            content => {
               body => "Hello",
            },
         );

         redact_event( $event );

         $outbound_client->send_event(
            event => $event,
            destination => $first_home_server,
         );
      })->then( sub {
         await_event_for( $creator, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{room_id} eq $room_id;

            assert_eq( $event->{sender}, $user_id,
               'event sender' );
            assert_deeply_eq( $event->{content}, {},
               'event content body' );

            Future->done(1);
         });
      });
   };
