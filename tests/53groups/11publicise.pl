test "Get/set local group publicity",
   deprecated_endpoints => 1,
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_invite_group_user( $creator, $group_id, $user );
      })->then( sub {
         matrix_accept_group_invite( $group_id, $user );
      })->then( sub {
         matrix_update_group_publicity( $group_id, $user, 1 );
      })->then( sub {
         matrix_get_group_publicity( $creator, $user )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( groups ) );
         assert_deeply_eq( $body->{groups}, [ $group_id ] );

         Future->done( 1 );
      });
   };

test "Bulk get group publicity",
   deprecated_endpoints => 1,
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ), remote_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $local_user, $remote_user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_invite_group_user( $creator, $group_id, $local_user );
      })->then( sub {
         matrix_accept_group_invite( $group_id, $local_user );
      })->then( sub {
         matrix_invite_group_user( $creator, $group_id, $remote_user );
      })->then( sub {
         matrix_accept_group_invite( $group_id, $remote_user );
      })->then( sub {
         matrix_update_group_publicity( $group_id, $local_user, 1 );
      })->then( sub {
         matrix_update_group_publicity( $group_id, $remote_user, 1 );
      })->then( sub {
         matrix_bulk_get_group_publicity( $creator, $local_user, $remote_user )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_deeply_eq( $body, {
            users => {
               $local_user->user_id => [ $group_id ],
               $remote_user->user_id => [ $group_id ],
            }
         } );

         Future->done( 1 );
      });
   };


sub matrix_update_group_publicity
{
   my ( $group_id, $user, $publicise ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/groups/$group_id/self/update_publicity",
      content => {
         publicise => $publicise ? JSON::true : JSON::false,
      },
   );
}

sub matrix_get_group_publicity
{
   my ( $user, $other_user ) = @_;

   my $other_user_id = $other_user->user_id;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/r0/publicised_groups/$other_user_id",
   );
}

sub matrix_bulk_get_group_publicity
{
   my ( $user, @users ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/r0/publicised_groups",
      content => {
         user_ids => [ map { $_->user_id } @users ],
      }
   );
}
