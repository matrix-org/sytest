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

test "Other clients can join the room",
   requires => [qw( clients first_room room_alias )],

   do => sub {
      my ( $CLIENTS, $FIRST_ROOM, $ROOM_ALIAS ) = @_;
      my ( undef, @other_clients ) = @$CLIENTS; # Ignore the first

      Future->needs_all( map {
         $_->join_room( $ROOM_ALIAS )
            ->then( sub {
               my ( $room ) = @_;
               $room->initial_sync->then_done( $room );
            } )
      } @other_clients )
         ->on_done( sub {
            my @other_rooms = @_;

            provide rooms => [ $FIRST_ROOM, @other_rooms ];
         });
   },

   provides => [qw( rooms )],
;

test "All clients see all room members initially",
   requires => [qw( clients rooms )],

   check => sub {
      my ( $CLIENTS, $ROOMS ) = @_;

      my @user_ids = map { $_->myself->user_id } @$CLIENTS;

      # Rooms should already be initialSync'ed by now, so ->members will be
      # immediately correct
      foreach my $room ( @$ROOMS ) {
         my @members = $room->joined_members;

         scalar @members == scalar @$CLIENTS or
            return Future->fail( "Room does not have the right number of members" );
         my %members_by_uid = map { $_->user->user_id => $_ } @members;

         exists $members_by_uid{$_} or return Future->fail( "Room does not have $_" )
            for @user_ids;
      }

      Future->done(1);
   },
;

test "All clients see presence state of all room members",
   requires => [qw( clients rooms )],

   wait_time => 10,  # This might not be immediate, as it doesn't come in /state
   check => sub {
      my ( $CLIENTS, $ROOMS ) = @_;

      my @user_ids = map { $_->myself->user_id } @$CLIENTS;

      foreach my $client ( @$CLIENTS ) {
         foreach my $user_id ( @user_ids ) {
            $client->cached_presence( $user_id ) eq "online" or
               return Future->fail( "Client does not have presence for $user_id" );
         }
      }

      Future->done(1);
   },
;
