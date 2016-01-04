my $alias_localpart = "#another-alias";

my $user_fixture = local_user_fixture();

my $room_fixture = fixture(
   requires => [ $user_fixture ],

   setup => sub {
      my ( $user ) = @_;

      matrix_create_room( $user );
   },
);

test "PUT /directory/room/:room_alias creates alias",
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_create_room_alias can_lookup_room_alias )],

   do => sub {
      my ( $user, $room_id ) = @_;
      my $server_name = $user->http->server_name;
      my $room_alias = "${alias_localpart}:$server_name";

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/directory/room/$room_alias",

         content => {
            room_id => $room_id,
         },
      );
   },

   check => sub {
      my ( $user, $room_id ) = @_;
      my $server_name = $user->http->server_name;
      my $room_alias = "${alias_localpart}:$server_name";

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id servers ));
         assert_json_list( $body->{servers} );

         $body->{room_id} eq $room_id or die "Expected room_id";

         Future->done(1);
      });
   };
