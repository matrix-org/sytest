use JSON qw( encode_json );

test "Can pass a JSON filter as a query parameter",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      my ( $room_id );

      matrix_create_room_synced( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => encode_json( {
            room => {
               state => { types => [ "m.room.member" ] },
               timeline => { limit => 0 },
            }
         }));
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         assert_json_empty_list( $room->{timeline}{events} );

         @{ $room->{state}{events} } == 1
            or die "Expected a single state event because of the filter";

         $room->{state}{events}[0]{type} eq "m.room.member"
            or die "Expected a single member event because of the filter";

         Future->done(1);
      });
   };


test "Can request federation format via the filter",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id_1 );

      my $filter = {
         event_format => 'federation',
         room => { timeline => { limit => 1 } },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $user )
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message_synced( $user, $room_id,
            body => "Test message",
         );
      })->then( sub {
         ( $event_id_1 ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         log_if_fail "sync room result", $room;

         assert_json_keys( $room, qw( timeline state ephemeral ));
         assert_json_keys( $room->{timeline}, qw( events limited prev_batch ));

         assert_eq( scalar @{ $room->{timeline}{events} }, 1, "timeline event count" );

         assert_json_keys(
            $room->{timeline}{events}[0], qw(
               event_id content room_id sender origin origin_server_ts type
               prev_events auth_events depth hashes signatures
            )
         );

         assert_eq( $room->{timeline}{events}[0]{content}{body}, "Test message", "timeline message" );
         assert_eq( $room->{timeline}{events}[0]{event_id}, $event_id_1, "timeline event id" );

         Future->done(1);
      });
  };
