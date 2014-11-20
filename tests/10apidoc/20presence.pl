test "GET /presence/:user_id/status fetches initial status",
   requires => [qw( do_request_json )],

   check => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/presence/:user_id/status",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( presence last_active_ago ));
         require_json_number( $body->{last_active_ago} );
         $body->{last_active_ago} >= 0 or
            die "Expected last_active_ago non-negative";

         Future->done(1);
      });
   };

my $status_msg = "Testing something";

test "PUT /presence/:user_id/status updates my presence",
   requires => [qw( do_request_json )],

   do => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/presence/:user_id/status",

         content => {
            presence   => "online",
            status_msg => $status_msg,
         },
      )
   },

   check => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/presence/:user_id/status",
      )->then( sub {
         my ( $body ) = @_;

         ( $body->{status_msg} // "" ) eq $status_msg or
            die "Incorrect status_msg";

         provide can_set_presence => 1;

         Future->done(1);
      });
   };
