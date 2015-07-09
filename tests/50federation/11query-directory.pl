local *SyTest::Federation::Server::on_request_federation_v1_query_directory = sub {
   my $self = shift;
   my ( $req ) = @_;

   my $server_name = $self->{federation_params}->server_name;

   Future->done( {
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
