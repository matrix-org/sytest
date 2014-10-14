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
