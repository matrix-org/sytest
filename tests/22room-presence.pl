test "User presence changes are announced to a room",
   requires => [qw( clients rooms )],

   do => sub {
      my ( $CLIENTS, $ROOMS ) = @_;
      my ( $first_client ) = @$CLIENTS;

      $first_client->set_presence( unavailable => "Gone testin'" )
   },

   wait_time => 3,
   check => sub {
      my ( $CLIENTS, $ROOMS ) = @_;
      my ( $first_client ) = @$CLIENTS;
      my $user_id = $first_client->myself->user_id;

      foreach my $client ( @$CLIENTS ) {
         $client->cached_presence( $user_id ) eq "unavailable" or
            return Future->fail( "Incorrect presence for $user_id" );
      }

      Future->done(1);
   };
