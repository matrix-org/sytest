test "GET /events initially",
   requires => [qw( first_http_client access_token )],

   check => sub {
      my ( $http, $access_token ) = @_;

      $http->do_request_json(
         method => "GET",
         uri    => "/events",
         params => { access_token => $access_token, timeout => 0 },
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";

         defined $body->{$_} or die "Expected '$_'\n" for qw( start end );

         ref $body->{chunk} eq "ARRAY" or die "Expected 'chunk' as a JSON list\n";

         # We can't be absolutely sure that there won't be any events yet, so
         # don't check that.

         Future->done(1);
      });
   };
