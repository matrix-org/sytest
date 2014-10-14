test "GET /presence/:user_id/status fetches initial status",
   requires => [qw( first_http_client can_login )],

   check => sub {
      my ( $http, $login ) = @_;
      my ( $user_id, $access_token ) = @$login;

      $http->do_request_json(
         method => "GET",
         uri    => "/presence/$user_id/status",
         params => { access_token => $access_token },
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";

         defined $body->{presence} or die "Expected 'presence' key\n";

         Future->done(1);
      });
   };

my $status_msg = "Testing something";

test "PUT /presence/:user_id/status updates my presence",
   requires => [qw( first_http_client can_login )],

   check => sub {
      my ( $http, $login ) = @_;
      my ( $user_id, $access_token ) = @$login;

      $http->do_request_json(
         method => "GET",
         uri    => "/presence/$user_id/status",
         params => { access_token => $access_token },
      )->then( sub {
         my ( $body ) = @_;
         Future->done( $body->{status_msg} eq $status_msg );
      });
   },

   do => sub {
      my ( $http, $login ) = @_;
      my ( $user_id, $access_token ) = @$login;

      $http->do_request_json(
         method => "PUT",
         uri    => "/presence/$user_id/status",
         params => { access_token => $access_token },

         content => {
            presence   => "online",
            status_msg => $status_msg,
         },
      )
   };
