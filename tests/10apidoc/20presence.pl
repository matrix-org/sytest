test "GET /presence/:user_id/status fetches initial status",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/presence/:user_id/status",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( presence last_active_ago ));
         json_number_ok( $body->{last_active_ago} );
         $body->{last_active_ago} >= 0 or die "Expected last_active_ago non-negative";

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
         Future->done( ( $body->{status_msg} // "" ) eq $status_msg );
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
