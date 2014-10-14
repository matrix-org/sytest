test "GET /events initially",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/events",
         params => { timeout => 0 },
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
