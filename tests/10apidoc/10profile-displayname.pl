my $user_fixture = local_user_fixture();

my $displayname = "Testing Displayname";

test "PUT /profile/:user_id/displayname sets my name",
   requires => [ $user_fixture ],

   provides => [qw( can_set_displayname )],

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

         provide can_set_displayname => 1;

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
   requires => [ $main::API_CLIENTS, $user_fixture,
                 qw( can_set_displayname )],

   provides => [qw( can_get_displayname )],

   check => sub {
      my ( $clients, $user ) = @_;
      my $http = $clients->[0];
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

         provide can_get_displayname => 1;

         Future->done(1);
      });
   };
