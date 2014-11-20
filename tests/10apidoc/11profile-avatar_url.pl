my $avatar_url = "http://somewhere/my-pic.jpg";

test "PUT /profile/:user_id/avatar_url sets my avatar",
   requires => [qw( do_request_json )],

   check => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/profile/:user_id/avatar_url",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( avatar_url ));

         $body->{avatar_url} eq $avatar_url or
            die "Expected avatar_url to be '$avatar_url'";

         provide can_set_avatar_url => 1;

         Future->done(1);
      });
   },

   do => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/profile/:user_id/avatar_url",

         content => {
            avatar_url => $avatar_url,
         },
      );
   };

test "GET /profile/:user_id/avatar_url publicly accessible",
   requires => [qw( first_http_client user can_set_avatar_url )],

   check => sub {
      my ( $http, $user ) = @_;
      my $user_id = $user->user_id;

      $http->do_request_json(
         method => "GET",
         uri    => "/profile/$user_id/avatar_url",
         # no access_token
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( avatar_url ));

         $body->{avatar_url} eq $avatar_url or
            die "Expected avatar_url to be '$avatar_url'";

         Future->done(1);
      });
   };
