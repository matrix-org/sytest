# Each user should initially only see their own presence state
test "Users see their own initial presence",
   wait_time => 10,
   check => sub {
      my ( $CLIENTS ) = @_;
      foreach ( @$CLIENTS ) {
         my $port = $_->port;

         $_->cached_presence( "\@u-$port:localhost:$port" ) eq "online" or
            return Future->fail( "Incorrect presence for $port" );

         keys %{ $_->cached_presence } > 1 and
            return Future->fail( "Presence for $port can see too much" );
      }
      return Future->done(1);
   },
;
