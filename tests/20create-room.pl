test "A room can be created",
   requires => [qw( clients )],

   do => sub {
      my ( $CLIENTS ) = @_;
      my $first_client = $CLIENTS->[0]; # We just use the first client

      $first_client->create_room( "test-room" )
         ->on_done( sub {
            my ( $room, $alias ) = @_;

            provide first_room => $room;
            provide room_alias => $alias;
         });
   },

   provides => [qw( first_room room_alias )],
;
