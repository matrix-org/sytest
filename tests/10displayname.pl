test "Users can set their displayname",
   do => sub {
      my ( $CLIENTS ) = @_;

      Future->needs_all(
         map {
            my $port = $_->port;

            $_->set_displayname( "User on port $port" )
               ->on_done_diag( "Set User $port displayname" )
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
   },
;
