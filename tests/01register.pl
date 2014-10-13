test "New users can be registered",
   requires => [qw( clients )],

   do => sub {
      my ( $CLIENTS ) = @_;

      Future->needs_all( map {
         my $client = $_;
         my $port = $client->port;

         $client->register( user_id => "u-$port", password => "f00b4r" )
            ->then( sub { $client->start } )
            ->then_done( $client );
      } @$CLIENTS )
         ->on_done( sub {
            my @users = @_;
            provide users => \@users;
         });
   },

   provides => [qw( users )];

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
