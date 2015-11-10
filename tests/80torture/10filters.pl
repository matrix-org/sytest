my $INVALID_FILTERS = [
   { presence => "not_an_object" },
   { room => { timeline => "not_an_object" } },
   { room => { state => "not_an_object" } },
   { room => { ephemeral => "not_an_object" } },
   { room => { private_user_data => "not_an_object" } },
   { room => { timeline => { "rooms" => "not_a_list" } } },
   { room => { timeline => { "not_rooms" => "not_a_list" } } },
   { room => { timeline => { "senders" => "not_a_list" } } },
   { room => { timeline => { "not_senders" => "not_a_list" } } },
   { room => { timeline => { "types" => "not_a_list" } } },
   { room => { timeline => { "not_types" => "not_a_list"} } },
   { room => { timeline => { "types" => [ 0 ] } } },
   { room => { timeline => { "rooms" => [ "not_a_room_id" ] } } },
   { room => { timeline => { "senders" => [ "not_a_sender_id" ] } } },
];


test "Check creating invalid filters returns 4xx",
   requires => [ local_user_fixture( with_events => 0 ) ],

   check => sub {
      my ( $user ) = @_;

      Future->wait_all( map {
         my $filter = $_;
         matrix_create_filter( $user, $_ )
            ->main::expect_http_4xx
            ->on_fail( sub { log_if_fail "Filter:", $filter; });
      } @{ $INVALID_FILTERS } )->then( sub {
         # Wait for all the requests to finish, then check that all of them
         # succeeded.
         Future->needs_all( @_ );
      });
   };
