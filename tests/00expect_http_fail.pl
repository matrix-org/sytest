use Future 0.33; # ->then catch semantics

sub gen_expect_failure
{
   my ( $name, $match ) = @_;

   return sub {
      my ( $f ) = @_;

      $f->then_with_f(
         sub {  # done
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
   expect_http_4xx expect_http_403
);

*expect_http_4xx = gen_expect_failure( '4xx' => qr/^4/ );

*expect_http_403 = gen_expect_failure( '403' => qr/^403/ );
