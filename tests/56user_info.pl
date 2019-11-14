use URI::Escape qw( uri_escape );

=head2 matrix_get_user_info

   my $info = matrix_get_user_info( $as_user, $user );

While acting as a given user, retrieve information about a given user using the
CS /user/:user_id/info endpoint.

=cut

sub matrix_get_user_info
{
   my ( $as_user, $user ) = @_;

   my $user_id = uri_escape( $user->user_id );
   do_request_json_for( $as_user,
      method  => "GET",
      uri     => "/r0/user/$user_id/info",
      content => {},
   );
};
push our @EXPORT, qw( matrix_get_user_info );

test "User info endpoint requires authentication",
   requires => [
      $main::API_CLIENTS[0],
      local_user_fixture(),
   ],

   do => sub {
      my ( $http, $user, ) = @_;

      # Check that we can't request this endpoint without authentication
      my $user_id = uri_escape( $user->user_id );
      $http->do_request_json(
         method  => "GET",
         uri     => "/r0/user/$user_id/info",
         content => {},
      )->main::expect_http_401;
   };

foreach my $user_type ( qw ( local remote ) ) {
   test "User info endpoint correctly specifies a deactivated $user_type user",
      requires => [
         local_user_fixture(),
         ( $user_type eq "local" ? local_user_fixture() : remote_user_fixture() ),
      ],

      do => sub {
         my ( $user1, $user2 ) = @_;

         # Check if the user is deactivated (they should not be)
         matrix_get_user_info(
            $user1, $user2
         )->then( sub {
            my ( $body, ) = @_;

            assert_eq( $body->{deactivated}, JSON::false, "user status before deactivation" );

            # Deactivate the user
            matrix_deactivate_account( $user2 );
         })->then( sub {
            # Check if the user is deactivated again (they should be)
            matrix_get_user_info( $user1, $user2 );
         })->then( sub {
            my ( $body, ) = @_;

            assert_eq( $body->{deactivated}, JSON::true, "user status after deactivation" );

            Future->done( 1 );
         });
      };
};

foreach my $user_type ( qw ( local remote ) ) {
   test "User info endpoint correctly specifies an expired $user_type user",
      requires => [
         ( $user_type eq "local" ? local_admin_fixture() : remote_admin_fixture() ),
         ( $user_type eq "local" ? local_user_fixture() : remote_user_fixture() ),
      ],

      do => sub {
         my ( $admin, $user ) = @_;

         # Check if the user is expired (they should not be)
         matrix_get_user_info(
            $admin, $user
         )->then( sub {
            my ( $body, ) = @_;

            assert_eq( $body->{expired}, JSON::false, "user status before expiration" );

            log_if_fail $user->user_id, "username";

            # Expire the user
            do_request_json_for( $admin,
               method  => "POST",
               full_uri => "/_synapse/admin/v1/account_validity/validity",
               content => {
                  "user_id" => $user->user_id,
                  "expiration_ts" => 0,
               },
            );
         })->then( sub {
            my ( $body, ) = @_;

            assert_eq( $body->{expiration_ts}, 0 );

            # Check if the user is deactivated again (they should be)
            matrix_get_user_info( $admin, $user );
         })->then( sub {
            my ( $body, ) = @_;

            assert_eq( $body->{expired}, JSON::true, "user status after expiration" );

            Future->done( 1 );
         });
      };
};
