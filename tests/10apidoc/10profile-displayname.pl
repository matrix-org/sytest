my $user_fixture = local_user_fixture();

my $displayname = "Testing Displayname";

test "PUT /profile/:user_id/displayname sets my name",
   requires => [ $user_fixture ],

   proves => [qw( can_set_displayname )],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/profile/:user_id/displayname",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( displayname ));

         $body->{displayname} eq $displayname or
            die "Expected displayname to be '$displayname'";

         Future->done(1);
      });
   },

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/profile/:user_id/displayname",

         content => {
            displayname => $displayname,
         },
      );
   };

test "GET /profile/:user_id/displayname publicly accessible",
   requires => [ $main::API_CLIENTS[0], $user_fixture,
                 qw( can_set_displayname )],

   proves => [qw( can_get_displayname )],

   check => sub {
      my ( $http, $user ) = @_;
      my $user_id = $user->user_id;

      $http->do_request_json(
         method => "GET",
         uri    => "/api/v1/profile/$user_id/displayname",
         # no access_token
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( displayname ));

         $body->{displayname} eq $displayname or
            die "Expected displayname to be '$displayname'";

         Future->done(1);
      });
   };
