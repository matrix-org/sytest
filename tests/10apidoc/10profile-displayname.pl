my $displayname = "Testing Displayname";

test "PUT /profile/:user_id/displayname sets my name",
   requires => [qw( do_request_json )],

   provides => [qw( can_set_displayname )],

   check => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/profile/:user_id/displayname",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( displayname ));

         $body->{displayname} eq $displayname or
            die "Expected displayname to be '$displayname'";

         provide can_set_displayname => 1;

         Future->done(1);
      });
   },

   do => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/profile/:user_id/displayname",

         content => {
            displayname => $displayname,
         },
      );
   };

test "GET /profile/:user_id/displayname publicly accessible",
   requires => [qw( first_http_client user can_set_displayname )],

   check => sub {
      my ( $http, $user ) = @_;
      my $user_id = $user->user_id;

      $http->do_request_json(
         method => "GET",
         uri    => "/profile/$user_id/displayname",
         # no access_token
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( displayname ));

         $body->{displayname} eq $displayname or
            die "Expected displayname to be '$displayname'";

         Future->done(1);
      });
   };
