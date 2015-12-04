my $user_fixture = local_user_fixture();

my $avatar_url = "http://somewhere/my-pic.jpg";

test "PUT /profile/:user_id/avatar_url sets my avatar",
   requires => [ $user_fixture ],

   proves => [qw( can_set_avatar_url )],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/profile/:user_id/avatar_url",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( avatar_url ));

         $body->{avatar_url} eq $avatar_url or
            die "Expected avatar_url to be '$avatar_url'";

         Future->done(1);
      });
   },

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/profile/:user_id/avatar_url",

         content => {
            avatar_url => $avatar_url,
         },
      );
   };

test "GET /profile/:user_id/avatar_url publicly accessible",
   requires => [ $main::API_CLIENTS[0], $user_fixture,
                 qw( can_set_avatar_url )],

   check => sub {
      my ( $http, $user ) = @_;
      my $user_id = $user->user_id;

      $http->do_request_json(
         method => "GET",
         uri    => "/api/v1/profile/$user_id/avatar_url",
         # no access_token
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( avatar_url ));

         $body->{avatar_url} eq $avatar_url or
            die "Expected avatar_url to be '$avatar_url'";

         Future->done(1);
      });
   };
