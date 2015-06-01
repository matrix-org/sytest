prepare "Creating test assertion helpers",
   provides => [qw( expect_http_4xx )],

   do => sub {

      provide expect_http_4xx => sub {
         my ( $f ) = @_;

         $f->then(
            sub {  # done
               Future->fail( "Expected to receive an HTTP 4xx failure but it succeeded" )
            },
            sub {  # fail
               my ( undef, $name, $response ) = @_;
               $name and $name eq "http" and $response and $response->code =~ m/^4/ and
                  return Future->done( $response );
               Future->fail( @_ );
            },
         );
      };

      Future->done;
   };
