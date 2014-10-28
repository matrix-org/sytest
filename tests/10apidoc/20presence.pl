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
         $body->{last_active_ago} >= 0 or
            die "Expected last_active_ago non-negative";

         Future->done(1);
      });
   };

my $status_msg = "Testing something";

test "PUT /presence/:user_id/status updates my presence",
   requires => [qw( do_request_json_authed )],

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
   },

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
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

test "GET /events sees my new presence",
   requires => [qw( GET_new_events user can_set_presence )],

   check => sub {
      my ( $GET_new_events, $user ) = @_;

      $GET_new_events->( "m.presence" )->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            my $content = $event->{content};
            json_keys_ok( $content, qw( user_id status_msg ));

            next unless $content->{user_id} eq $user->user_id;
            $found++;

            $content->{status_msg} eq $status_msg or
               die "Expected status_msg to be $status_msg";
         }

         $found or
            die "Did not find expected presence event";

         Future->done(1);
      });
   };
