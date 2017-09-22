test "Get/set local group publicity",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_invite_group_users( $creator, $group_id, $user );
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

         matrix_get_group_summary( $user, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Summary body", $body;

         assert_json_keys( $body, qw( user ) );

         assert_eq( $body->{user}{is_public}, 1 );

         matrix_update_group_publicity( $group_id, $user, 0 );
      })->then( sub {
         matrix_get_group_summary( $user, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Summary body 2", $body;

         assert_json_keys( $body, qw( user ) );

         assert_eq( $body->{user}{is_public}, 0 );

         Future->done( 1 );
      });
   };

test "Bulk get group publicity",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ), remote_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $local_user, $remote_user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_invite_group_users( $creator, $group_id, $local_user );
      })->then( sub {
         matrix_accept_group_invite( $group_id, $local_user );
      })->then( sub {
         matrix_invite_group_users( $creator, $group_id, $remote_user );
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


push our @EXPORT, qw( matrix_update_group_publicity matrix_get_group_publicity matrix_bulk_get_group_publicity );


sub matrix_update_group_publicity
{
   my ( $group_id, $user, $publicise ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/self/update_publicity",
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
      uri    => "/unstable/publicised_groups/$other_user_id",
   );
}

sub matrix_bulk_get_group_publicity
{
   my ( $user, @users ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/unstable/publicised_groups",
      content => {
         user_ids => [ map { $_->user_id } @users ],
      }
   );
}
