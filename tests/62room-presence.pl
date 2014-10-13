test "User presence changes are announced to a room",
   requires => [qw( users rooms )],

   do => sub {
      my ( $USERS, $ROOMS ) = @_;
      my ( $first_client ) = @$USERS;

      $first_client->set_presence( unavailable => "Gone testin'" )
   },

   wait_time => 3,
   check => sub {
      my ( $USERS, $ROOMS ) = @_;
      my ( $first_client ) = @$USERS;
      my $user_id = $first_client->myself->user_id;

      foreach my $client ( @$USERS ) {
         $client->cached_presence( $user_id ) eq "unavailable" or
            return Future->fail( "Incorrect presence for $user_id" );
      }

      1;
   };
