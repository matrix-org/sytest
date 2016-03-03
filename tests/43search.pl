use List::Util qw( first );
use Future::Utils qw( repeat );


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
            uri     => "/r0/search",
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

         assert_json_keys( $body, qw( search_categories ) );
         assert_json_keys( $body->{search_categories}, qw ( room_events ) );

         my $room_events = $body->{search_categories}{room_events};
         assert_json_keys( $room_events, qw( count results ) );

         $room_events->{count} == 1 or die "Expected one search result";

         my $results = $room_events->{results};
         my $result = first { $_->{result}{event_id} eq $event_id } @$results;

         assert_json_keys( $result, qw( rank result ) );
         assert_json_keys( $result->{result}, qw(
            event_id room_id user_id content type
         ));

         $result->{result}{content}{body} eq "hello, world"
            or die "Unexpected event content in search result";

         Future->done(1);
      });
   };

test "Can back-paginate search results",
    requires => [ local_user_and_room_fixtures() ],

    check => sub {
        my ( $user, $room_id ) = @_;

        my ( @event_ids );

        my $search_query = {
            search_categories => {
                room_events => {
                    keys => [ "content.body" ],
                    search_term => "Message",
                    order_by => "recent",
                    filter => { limit => 10 },
                }
            }
        };

        repeat( sub {
            my $msgnum = $_[0];
            matrix_send_room_text_message( $user, $room_id,
                                           body => "Message number $msgnum" )
                ->on_done( sub { ( $event_ids[$msgnum] ) = @_ } )
        }, foreach => [ 0 .. 19 ] )->then( sub {
            do_request_json_for( $user,
                                 method  => "POST",
                                 uri     => "/r0/search",
                                 content => $search_query,
            );
        })->then( sub {
            my ( $body ) = @_;

            log_if_fail "First search result:", $body;

            assert_json_keys( $body, qw( search_categories ) );
            assert_json_keys( $body->{search_categories}, qw ( room_events ) );
            my $room_events = $body->{search_categories}{room_events};

            assert_json_keys( $room_events, qw( count results next_batch ) );
            assert_eq( $room_events->{count}, 20, 'event count' );

            my $results = $room_events->{results};
            assert_eq( scalar @$results, 10, 'search results' );

            assert_eq( $results->[0]{result}{event_id}, $event_ids[19],
                       'first result event_id' );
            assert_eq( $results->[9]{result}{event_id}, $event_ids[10],
                       'final result event_id' );

            my $next_batch = $room_events->{next_batch};

            do_request_json_for( $user,
                                 method  => "POST",
                                 uri     => "/r0/search",
                                 params  => { next_batch => $next_batch },
                                 content => $search_query,
            );
        })->then( sub {
            my ( $body ) = @_;

            log_if_fail "Second search result:", $body;

            assert_json_keys( $body, qw( search_categories ) );
            assert_json_keys( $body->{search_categories}, qw ( room_events ) );
            my $room_events = $body->{search_categories}{room_events};

            assert_json_keys( $room_events, qw( count results next_batch ) );
            assert_eq( $room_events->{count}, 20, 'event count' );

            my $results = $room_events->{results};
            assert_eq( scalar @$results, 10, 'search results' );

            assert_eq( $results->[0]{result}{event_id}, $event_ids[9],
                       'first result event_id' );
            assert_eq( $results->[9]{result}{event_id}, $event_ids[0],
                       'final result event_id' );

            my $next_batch = $room_events->{next_batch};

            do_request_json_for( $user,
                                 method  => "POST",
                                 uri     => "/r0/search",
                                 params  => { next_batch => $next_batch },
                                 content => $search_query,
            );
        })->then( sub {
            my ( $body ) = @_;

            log_if_fail "Third search result:", $body;

            assert_json_keys( $body, qw( search_categories ) );
            assert_json_keys( $body->{search_categories}, qw ( room_events ) );
            my $room_events = $body->{search_categories}{room_events};

            assert_json_keys( $room_events, qw( count results ) );
            not exists( $room_events->{next_batch} ) or die "unexpected next_batch";

            assert_eq( $room_events->{count}, 20, 'event count' );

            my $results = $room_events->{results};
            assert_eq( scalar @$results, 0, 'search results' );

            Future->done( 1 );
        });
    };
