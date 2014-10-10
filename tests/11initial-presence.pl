# Each user should initially only see their own presence state
test "Users see their own initial presence",
   requires => [qw( users )],

   wait_time => 10,
   check => sub {
      my ( $USERS ) = @_;
      foreach ( @$USERS ) {
         my $port = $_->port;

         $_->cached_presence( "\@u-$port:localhost:$port" ) eq "online" or
            return Future->fail( "Incorrect presence for $port" );

         keys %{ $_->cached_presence } > 1 and
            return Future->fail( "Presence for $port can see too much" );
      }
      return Future->done(1);
   };
