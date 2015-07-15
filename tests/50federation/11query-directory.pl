local *SyTest::Federation::Server::on_request_federation_v1_query_directory = sub {
   my $self = shift;
   my ( $req ) = @_;

   my $server_name = $self->server_name;

   Future->done( json => {
      room_id => "!the-room-id:$server_name",
      servers => [
         $server_name,
      ]
   } );
};

test "Outbound federation can query room alias directory",
   requires => [qw( do_request_json local_server_name
                    can_lookup_room_alias )],

   check => sub {
      my ( $do_request_json, $local_server_name ) = @_;
      my $room_alias = "#test:$local_server_name";

      $do_request_json->(
         method => "GET",
         uri    => "/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Query response", $body;

         require_json_keys( $body, qw( room_id servers ));

         $body->{room_id} eq "!the-room-id:$local_server_name" or
            die "Expected room_id to be '!the-room-id:$local_server_name'";

         require_json_list( $body->{servers} );
         @{ $body->{servers} } or
            die "Expected a non-empty server list";

         require_json_string( $_ ) for @{ $body->{servers} };

         Future->done(1);
      });
   };

test "Inbound federation can query room alias directory",
   requires => [qw( outbound_client do_request_json first_home_server
                    can_create_room_alias )],

   do => sub {
      my ( $outbound_client, $do_request_json, $first_home_server ) = @_;

      my $room_alias = "#50federation-11query-directory:$first_home_server";
      my $room_id = "!the-room-id-for-test:example.org";

      $do_request_json->(
         method => "PUT",
         uri    => "/directory/room/$room_alias",

         content => {
            room_id => $room_id,
            servers => [ "example.org" ],  # TODO: Am I really allowed to do this?
         },
      )->then( sub {
         $outbound_client->do_request_json(
            method => "GET",
            uri    => "/query/directory",

            params => {
               room_alias => $room_alias,
            },
         )
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail "Query response", $body;

         require_json_keys( $body, qw( room_id servers ));

         $body->{room_id} eq $room_id or
            die "Expected room_id to be '$room_id'";

         require_json_list( $body->{servers} );

         @{ $body->{servers} } or
            die "Expected a non-empty server list";

         Future->done(1);
      });
   };
