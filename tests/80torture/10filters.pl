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
   requires => [qw( first_api_client )],

   check => sub {
      my ( $http ) = @_;

      matrix_register_user( $http, undef, with_events => 0 )->then( sub {
         my ( $user ) = @_;
         Future->needs_all( map {
            my $filter = $_;
            matrix_create_filter( $user, $_ )
               ->main::expect_http_4xx
               ->on_fail( sub { log_if_fail "Filter:", $filter; });
         } @{ $INVALID_FILTERS } );
      });
   };
