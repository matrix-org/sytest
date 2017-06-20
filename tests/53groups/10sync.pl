use Future::Utils qw( try_repeat_until_success );


test "Local group invites come down sync",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $creator, $user ) = @_;

      my $group_id;

      my $group_name = "Test Group";

      matrix_create_group( $creator,
         name => $group_name,
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_sync( $user );
      })->then( sub {
         matrix_invite_group_users( $creator, $group_id, $user );
      })->then( sub {
         try_repeat_until_success( sub {
            matrix_sync_again( $user )
            ->then( sub {
               my ( $body ) = @_;

               assert_json_keys( $body, qw( groups ) );
               assert_json_keys( $body->{groups}, qw( invite ) );

               assert_json_keys(  $body->{groups}{invite}, $group_id );

               Future->done( $body->{groups}{invite}{$group_id} );
            });
         })
      })->then( sub {
         my ( $invite ) = @_;

         assert_json_keys( $invite, qw( profile ) );
         assert_json_keys( $invite->{profile}, qw( name ) );
         assert_eq( $invite->{profile}{name}, $group_name );

         Future->done( 1 );
      });
   };


# TODO: Test group creator sees group come down stream
