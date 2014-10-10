test "Other clients can join the room",
   requires => [qw( clients first_room room_alias )],

   do => sub {
      my ( $CLIENTS, $FIRST_ROOM, $ROOM_ALIAS ) = @_;
      my ( undef, @other_clients ) = @$CLIENTS; # Ignore the first

      Future->needs_all( map {
         $_->join_room( $ROOM_ALIAS )
      } @other_clients )
         ->on_done( sub {
            my @other_rooms = @_;

            provide rooms => [ $FIRST_ROOM, @other_rooms ];
         });
   },

   provides => [qw( rooms )],
;
