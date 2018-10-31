test "Joinability comes down summary",
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_set_group_join_policy( $group_id, $creator, "open" );
      })->then( sub {
         matrix_get_group_summary( $creator, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Summary Body", $body;

         assert_json_keys( $body, qw( profile ) );
         assert_eq( $body->{profile}->{is_openly_joinable}, JSON::true );

         matrix_set_group_join_policy( $group_id, $creator, "invite" );
      })->then( sub {
         matrix_get_group_summary( $creator, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Summary Body", $body;

         assert_json_keys( $body, qw( profile ) );
         assert_eq( $body->{profile}->{is_openly_joinable}, JSON::false );

         Future->done( 1 );
      });
   };

test "Set group joinable and join it",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_set_group_join_policy( $group_id, $creator, "open" );
      })->then( sub {
         matrix_join_group( $group_id, $user );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( groups ) );
         assert_json_list( my $group_ids = $body->{groups} );

         assert_deeply_eq( $group_ids, [ $group_id ] );

         Future->done( 1 );
      });
   };

test "Group is not joinable by default",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_join_group( $group_id, $user );
      })->main::expect_http_403;
   };

test "Group is joinable over federation",
   requires => [ local_admin_fixture( with_events => 0 ), remote_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      matrix_create_group( $creator )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_set_group_join_policy( $group_id, $creator, "open" );
      })->then( sub {
         matrix_join_group( $group_id, $user );
      })->then( sub {
         matrix_get_joined_groups( $user );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( groups ) );
         assert_json_list( my $group_ids = $body->{groups} );

         assert_deeply_eq( $group_ids, [ $group_id ] );

         Future->done( 1 );
      });
   };

sub matrix_set_group_join_policy
{
   my ( $group_id, $user, $join_policy ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/groups/$group_id/settings/m.join_policy",
      content => {
         "m.join_policy" => {
             "type" => $join_policy,
         },
      },
   );
}
