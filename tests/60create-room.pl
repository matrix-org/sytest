test "A room can be created",
   requires => [qw( users )],

   do => sub {
      my ( $USERS ) = @_;
      my $first_user = $USERS->[0]; # We just use the first client

      $first_user->create_room( "test-room" )
         ->on_done( sub {
            my ( $room, $alias ) = @_;

            provide first_room => $room;
            provide legacy_room_alias => $alias;
         });
   },

   provides => [qw( first_room legacy_room_alias )];

test "Other clients can join the room",
   requires => [qw( users first_room legacy_room_alias )],

   do => sub {
      my ( $USERS, $FIRST_ROOM, $ROOM_ALIAS ) = @_;
      my ( undef, @other_users ) = @$USERS; # Ignore the first

      Future->needs_all( map {
         $_->join_room( $ROOM_ALIAS )
      } @other_users )
         ->on_done( sub {
            my @other_rooms = @_;

            provide rooms => [ $FIRST_ROOM, @other_rooms ];
         });
   },

   provides => [qw( rooms )];

test "All clients see presence state of all room members",
   requires => [qw( users rooms )],

   wait_time => 10,  # This might not be immediate, as it doesn't come in /state
   check => sub {
      my ( $USERS, $ROOMS ) = @_;

      my @user_ids = map { $_->myself->user_id } @$USERS;

      foreach my $client ( @$USERS ) {
         foreach my $user_id ( @user_ids ) {
            ( $client->cached_presence( $user_id ) // "" ) eq "online" or
               return Future->fail( "Client does not have presence for $user_id" );
         }
      }

      1;
   };
