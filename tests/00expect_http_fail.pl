use Future 0.33; # ->then catch semantics

use Carp;

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

   check_http_code
);

*expect_http_302 = gen_expect_failure( '302' => qr/^302/ );

*expect_http_4xx = gen_expect_failure( '4xx' => qr/^4/ );

*expect_http_400 = gen_expect_failure( '400' => qr/^400/ );

*expect_http_401 = gen_expect_failure( '401' => qr/^401/ );

*expect_http_403 = gen_expect_failure( '403' => qr/^403/ );

*expect_http_404 = gen_expect_failure( '404' => qr/^404/ );

*expect_http_413 = gen_expect_failure( '413' => qr/^413/ );

*expect_http_error = gen_expect_failure( '4xx or 5xx' => qr/^[45]/ );

=head2 check_http_code

   $f_out = check_http_code( $f_in, %resultmap )
   $f_out = $f_in->main::check_http_code( %resultmap )

A utility wrapper around a L<Future> that normally returns HTTP responses
(such as those returned by C<do_json_for> and similar).

With an empty C<%resultmap> the function is transparent; the result of its
return future is whatever the input future's result was. However, keys in
C<%resultmap> cause different results for different HTTP status codes.

Each key in C<%resultmap> is either a numeric HTTP result code (e.g. C<200>),
a result code category (e.g. C<4xx>) or the special string C<"fail">, which
applies to failures that didn't even result in an HTTP response at all.

The corresponding value decides what alternative result the output future
should provide. C<"ok"> means it should return a single scalar true value,
C<"redo"> means it should return a single scalar false value (the reason being
this is likely to be used inside a C<repeat_until_true> block, thus causing
the block to repeat).

=cut

sub check_http_code
{
   my $f = shift;
   my %resultmap = @_;

   my $interpret_code = sub {
      my ( $f, $code ) = @_;

      my $outcome = $resultmap{$code} //
                    $resultmap{ substr( $code, 0, 1 ) . "xx" };

      if( !defined $outcome ) {
         return $f;
      }
      elsif( $outcome eq "ok" ) {
         return Future->done(1);
      }
      elsif( $outcome eq "redo" ) {
         return Future->done(0);
      }
      else {
         croak "Outcome '$outcome' not recognised";
      }
   };

   return $f->then_with_f(
      sub {  # done
         my ( $f, $body, $response ) = @_;
         $interpret_code->( $f, $response ? $response->code : "200" );
      },
      http => sub {  # catch http
         my ( $f, undef, $name, $response ) = @_;
         $interpret_code->( $f, $response ? $response->code : "fail" );
      },
   );
}
