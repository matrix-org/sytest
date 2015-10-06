sub gen_expect_failure
{
   my ( $name, $match ) = @_;

   return sub {
      my ( $f ) = @_;

      $f->then(
         sub {  # done
            Future->fail( "Expected to receive an HTTP $name failure but it succeeded" )
         },
         sub {  # fail
            my ( undef, $name, $response ) = @_;

            $name and $name eq "http" and
               $response and $response->code =~ $match and
                  return Future->done( $response );

            Future->fail( @_ );
         },
      );
   };
}

our @EXPORT = qw(
   expect_http_4xx expect_http_403 expect_http_404
);

*expect_http_4xx = gen_expect_failure( '4xx' => qr/^4/ );

*expect_http_403 = gen_expect_failure( '403' => qr/^403/ );

*expect_http_404 = gen_expect_failure( '404' => qr/^404/ );
