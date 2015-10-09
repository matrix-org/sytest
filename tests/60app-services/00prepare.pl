use Future::Utils qw( repeat );

prepare "Creating special AS user",
   requires => [qw( first_api_client as_credentials )],

   provides => [qw( as_user )],

   do => sub {
      my ( $http, $as_credentials ) = @_;
      my ( $user_id, $token ) = @$as_credentials;

      provide as_user => User( $http, $user_id, $token, undef, undef, [], undef );

      Future->done(1);
   };

prepare "Creating test helper functions",
   requires => [qw( hs2as_token )],

   provides => [qw( await_as_event )],

   do => sub {
      my ( $hs2as_token ) = @_;

      # Map event types to ARRAYs of Futures
      my %futures_by_type;

      provide await_as_event => sub {
         my ( $type ) = @_;
         my $failmsg = SyTest::CarpByFile::shortmess(
            "Timed out waiting for an AS event of type $type"
         );

         push @{ $futures_by_type{$type} }, my $f = $loop->new_future;

         return Future->wait_any(
            $f,

            delay( 10 )
               ->then_fail( $failmsg ),
         );
      };

      my $f = repeat {
         await_http_request( qr{^/appserv/transactions/\d+$}, sub { 1 },
            timeout => 0,
         )->then( sub {
            my ( $request ) = @_;

            # Respond immediately to AS
            $request->respond_json( {} );

            my $access_token = $request->query_param( "access_token" );

            defined $access_token or
               die "Expected HS to provide an access_token";
            $access_token eq $hs2as_token or
               die "HS did not provide the correct token";

            foreach my $event ( @{ $request->body_from_json->{events} } ) {
               my $type = $event->{type};

               my $queue = $futures_by_type{$type};

               # Ignore any cancelled ones
               shift @$queue while $queue and @$queue and $queue->[0]->is_cancelled;

               if( $queue and my $f = shift @$queue ) {
                  $f->done( $event );
               }
               else {
                  print STDERR "Ignoring incoming AS event of type $type\n";
               }
            }

            Future->done;
         })
      } while => sub { not $_[0]->failure };

      $f->on_fail( sub { die $_[0] } );

      # lifecycle it
      $f->on_cancel( sub { undef $f } );

      Future->done(1);
   };
