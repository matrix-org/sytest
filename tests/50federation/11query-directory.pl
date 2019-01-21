test "Outbound federation can query room alias directory",
   requires => [ $main::INBOUND_SERVER, $main::SPYGLASS_USER,
                qw( can_lookup_room_alias )],

   check => sub {
      my ( $inbound_server, $user ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $room_alias = "#test:$local_server_name";

      require_stub $inbound_server->await_request_query_directory( $room_alias )
         ->on_done( sub {
            my ( $req ) = @_;

            $req->respond_json( {
               room_id => "!the-room-id:$local_server_name",
               servers => [
                  $local_server_name,
               ]
            } );
         });

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Query response", $body;

         assert_json_keys( $body, qw( room_id servers ));

         $body->{room_id} eq "!the-room-id:$local_server_name" or
            die "Expected room_id to be '!the-room-id:$local_server_name'";

         assert_json_nonempty_list( $body->{servers} );

         assert_json_string( $_ ) for @{ $body->{servers} };

         Future->done(1);
      });
   };

test "Inbound federation can query room alias directory",
   # TODO(paul): technically this doesn't need local_user_fixture(), if we had
   #   some user we could assert can perform media/directory/etc... operations
   #   but doesn't mutate any of its own state, or join rooms, etc...
   requires => [ $main::OUTBOUND_CLIENT, $main::HOMESERVER_INFO[0],
                 local_user_fixture(), room_alias_fixture(),
                 qw( can_create_room_alias )],

   do => sub {
      my ( $outbound_client, $info, $user, $room_alias ) = @_;
      my $first_home_server = $info->server_name;

      my $room_id;

      matrix_create_room( $user )
      ->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $user,
            method => "PUT",
            uri    => "/r0/directory/room/$room_alias",

            content => {
               room_id => $room_id,
               servers => [ "example.org" ],  # TODO: Am I really allowed to do this?
            },
         )
      })->then( sub {
         $outbound_client->do_request_json(
            method   => "GET",
            hostname => $first_home_server,
            uri      => "/v1/query/directory",

            params => {
               room_alias => $room_alias,
            },
         )
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Query response", $body;

         assert_json_keys( $body, qw( room_id servers ));

         $body->{room_id} eq $room_id or
            die "Expected room_id to be '$room_id'";

         assert_json_nonempty_list( $body->{servers} );

         Future->done(1);
      });
   };
