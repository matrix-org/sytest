my $alias_localpart = "#another-alias";

test "PUT /directory/room/:room_alias creates alias",
   requires => [qw( do_request_json room_id first_home_server
                    can_create_room )],

   provides => [qw( can_create_room_alias )],

   do => sub {
      my ( $do_request_json, $room_id, $first_home_server ) = @_;
      my $room_alias = "${alias_localpart}:$first_home_server";

      $do_request_json->(
         method => "PUT",
         uri    => "/directory/room/$room_alias",

         content => {
            room_id => $room_id,
         },
      );
   },

   check => sub {
      my ( $do_request_json, $room_id, $first_home_server ) = @_;
      my $room_alias = "${alias_localpart}:$first_home_server";

      $do_request_json->(
         method => "GET",
         uri    => "/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id servers ));
         require_json_list( $body->{servers} );

         $body->{room_id} eq $room_id or die "Expected room_id";

         provide can_create_room_alias => 1;

         Future->done(1);
      });
   };
