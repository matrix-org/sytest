test "Users can set their displayname",
   requires => [qw( clients )],

   do => sub {
      my ( $CLIENTS ) = @_;

      Future->needs_all(
         map {
            my $port = $_->port;

            $_->set_displayname( "User on port $port" )
         } @$CLIENTS
      );
   },

   check => sub {
      my ( $CLIENTS ) = @_;

      Future->needs_all(
         map {
            my $port = $_->port;

            $_->get_displayname->then( sub {
               my ( $name ) = @_;
               $name eq "User on port $port" ? Future->done
                  : Future->fail( "User port $port does not have expected name" );
            })
         } @$CLIENTS
      )->then_done( 1 );
   };
