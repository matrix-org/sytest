use Future 0.33; # ->then catch semantics

sub gen_expect_failure
{
   my ( $name, $match ) = @_;

   return sub {
      my ( $f ) = @_;

      $f->then_with_f(
         sub {  # done
            my ( undef, $response ) = @_;

            log_if_fail "Response", $response;
            Future->fail( "Expected to receive an HTTP $name failure but it succeeded" )
         },
         http => sub {  # catch http
            my ( $f, undef, $name, $response ) = @_;

            $response and $response->code =~ $match and
               return Future->done( $response );

            return $f;
         },
      );
   };
}

our @EXPORT = qw(
   expect_http_302
   expect_http_4xx expect_http_400 expect_http_401 expect_http_403 expect_http_404
   expect_http_413 expect_http_error
);

*expect_http_302 = gen_expect_failure( '302' => qr/^302/ );

*expect_http_4xx = gen_expect_failure( '4xx' => qr/^4/ );

*expect_http_400 = gen_expect_failure( '400' => qr/^400/ );

*expect_http_401 = gen_expect_failure( '401' => qr/^401/ );

*expect_http_403 = gen_expect_failure( '403' => qr/^403/ );

*expect_http_404 = gen_expect_failure( '404' => qr/^404/ );

*expect_http_413 = gen_expect_failure( '413' => qr/^413/ );

*expect_http_error = gen_expect_failure( '4xx or 5xx' => qr/^[45]/ );
