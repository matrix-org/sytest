test "GET /presence/:user_id/status fetches initial status",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/presence/:user_id/status",
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";

         defined $body->{presence} or die "Expected 'presence' key\n";

         Future->done(1);
      });
   };

my $status_msg = "Testing something";

test "PUT /presence/:user_id/status updates my presence",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/presence/:user_id/status",
      )->then( sub {
         my ( $body ) = @_;
         Future->done( $body->{status_msg} eq $status_msg );
      });
   },

   do => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "PUT",
         uri    => "/presence/:user_id/status",

         content => {
            presence   => "online",
            status_msg => $status_msg,
         },
      )
   };
