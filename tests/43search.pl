test "Can search for an event by body",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      my ( $event_id );

      matrix_send_room_text_message( $user, $room_id,
         body => "hello, world",
      )->then( sub {
         ( $event_id ) = @_;

         do_request_json_for( $user,
            method  => "POST",
            uri     => "/api/v1/search",
            content => {
               search_categories => {
                  room_events => {
                     keys => [ "content.body" ],
                     search_term => "hello",
                  }
               }
            }
         );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Search Result Body:", $body;

         require_json_keys( $body, qw( search_categories ) );
         require_json_keys( $body->{search_categories}, qw ( room_events ) );

         my $room_events = $body->{search_categories}{room_events};
         require_json_keys( $room_events, qw( count results ) );

         $room_events->{count} == 1 or die "Expected one search result";

         my $result = $room_events->{results}{ $event_id };
         require_json_keys( $result, qw( rank result ) );
         require_json_keys( $result->{result}, qw(
            event_id room_id user_id content type
         ));

         $result->{result}{content}{body} eq "hello, world"
            or die "Unexpected event content in search result";

         Future->done(1);
      });
   };
