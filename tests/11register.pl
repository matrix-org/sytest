use JSON qw( decode_json );
use URI;

multi_test "Register with a recaptcha",
   requires => [qw( first_api_client await_http_request expect_http_4xx )],

   do => sub {
      my ( $http, $await_http_request, $expect_http_4xx ) = @_;

      Future->needs_all(
         $await_http_request->( "/recaptcha/api/siteverify", sub {1} )
            ->on_done( sub { pass "Got recaptcha verify request" } )
         ->then( sub {
            my ( $request ) = @_;

            my $params = $request->body_from_form;

            $params->{secret} eq "sytest_recaptcha_private_key" or
               die "Bad secret";

            $params->{response} eq "sytest_captcha_response" or
               die "Bad response";

            $request->respond_json(
               { success => JSON::true },
            );

            Future->done(1);
         }),

         $http->do_request_json(
            method  => "POST",
            uri     => "/v2_alpha/register",
            content => {
               username => "SYT-8-username",
               password => "my secret",
               auth     => {
                  type     => "m.login.recaptcha",
                  response => "sytest_captcha_response",
               },
            },
         )->$expect_http_4xx
         ->then( sub {
            my ( $response ) = @_;

            my $body = decode_json $response->content;

            log_if_fail "Body:", $body;

            require_json_keys( $body, qw(completed) );
            require_json_list( my $completed = $body->{completed} );

            @$completed == 1 or
               die "Expected one completed stage";

            $completed->[0] eq "m.login.recaptcha" or
               die "Expected to complete m.login.recaptcha";

            pass "Passed captcha validation";
            Future->done(1);
         }),
      )
   };
