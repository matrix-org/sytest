my $alias_localpart = "#another-alias";

my $user_preparer = local_user_preparer();

my $room_preparer = preparer(
   requires => [ $user_preparer ],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user );
   },
);

test "PUT /directory/room/:room_alias creates alias",
   requires => [qw( first_home_server ), $user_preparer, $room_preparer ],

   provides => [qw( can_create_room_alias can_lookup_room_alias )],

   do => sub {
      my ( $first_home_server, $user, $room_id ) = @_;
      my $room_alias = "${alias_localpart}:$first_home_server";

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/directory/room/$room_alias",

         content => {
            room_id => $room_id,
         },
      )->on_done( sub {
         provide can_create_room_alias => 1;
      })
   },

   check => sub {
      my ( $first_home_server, $user, $room_id ) = @_;
      my $room_alias = "${alias_localpart}:$first_home_server";

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id servers ));
         require_json_list( $body->{servers} );

         $body->{room_id} eq $room_id or die "Expected room_id";

         provide can_lookup_room_alias => 1;

         Future->done(1);
      });
   };
