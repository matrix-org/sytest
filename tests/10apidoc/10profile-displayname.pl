my $displayname = "Testing Displayname";

test "PUT /profile/:user_id/displayname sets my name",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/profile/:user_id/displayname",
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";

         defined $body->{displayname} or die "Expected 'displayname'\n";

         $body->{displayname} eq $displayname or die "Wrong displayname\n";

         provide can_set_displayname => 1;

         Future->done(1);
      });
   },

   do => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "PUT",
         uri    => "/profile/:user_id/displayname",

         content => {
            displayname => $displayname,
         },
      );
   };

test "GET /profile/:user_id/displayname publicly accessible",
   requires => [qw( first_http_client user_id can_set_displayname )],

   check => sub {
      my ( $http, $user_id ) = @_;

      $http->do_request_json(
         method => "GET",
         uri    => "/profile/$user_id/displayname",
         # no access_token
      )->then( sub {
         my ( $body ) = @_;

         ref $body eq "HASH" or die "Expected JSON object\n";

         defined $body->{displayname} or die "Expected 'displayname'\n";

         $body->{displayname} eq $displayname or die "Wrong displayname\n";

         Future->done(1);
      });
   };
