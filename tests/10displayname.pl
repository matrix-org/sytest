test "Users can set their displayname",
   requires => [qw( users )],

   do => sub {
      my ( $USERS ) = @_;

      Future->needs_all(
         map {
            my $port = $_->port;

            $_->set_displayname( "User on port $port" )
         } @$USERS
      );
   },

   check => sub {
      my ( $USERS ) = @_;

      Future->needs_all(
         map {
            my $port = $_->port;

            $_->get_displayname->then( sub {
               my ( $name ) = @_;
               $name eq "User on port $port" ? Future->done
                  : Future->fail( "User port $port does not have expected name" );
            })
         } @$USERS
      )->then_done( 1 );
   };
