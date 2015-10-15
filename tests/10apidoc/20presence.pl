my $preparer = local_user_preparer();

test "GET /presence/:user_id/status fetches initial status",
   requires => [ $preparer ],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/presence/:user_id/status",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( presence ));

         # TODO(paul): Newly-registered users might not yet have a
         #   last_active_ago
         # require_json_number( $body->{last_active_ago} );
         # $body->{last_active_ago} >= 0 or
         #    die "Expected last_active_ago non-negative";

         Future->done(1);
      });
   };

my $status_msg = "Testing something";

test "PUT /presence/:user_id/status updates my presence",
   requires => [ $preparer ],

   provides => [qw( can_set_presence )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/presence/:user_id/status",

         content => {
            presence   => "online",
            status_msg => $status_msg,
         },
      )
   },

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/presence/:user_id/status",
      )->then( sub {
         my ( $body ) = @_;

         ( $body->{status_msg} // "" ) eq $status_msg or
            die "Incorrect status_msg";

         provide can_set_presence => 1;

         Future->done(1);
      });
   };
