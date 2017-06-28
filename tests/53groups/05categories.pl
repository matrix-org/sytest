test "Add group category",
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_category_to_group( $user, $group_id, "some_cat",
            profile => { name => "Category Name" }
         );
      })->then( sub {
         matrix_get_group_category( $user, $group_id, "some_cat" );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw ( is_public profile ) );
         assert_deeply_eq( $body->{profile}, { name => "Category Name" } );

         Future->done( 1 );
      });
   };

test "Remove group category",
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_category_to_group( $user, $group_id, "some_cat" );
      })->then( sub {
         matrix_remove_category_from_group( $user, $group_id, "some_cat" );
      })->then( sub {
         matrix_get_group_category( $user, $group_id, "some_cat" );
      })->main::expect_http_404;
   };


test "Get group categories",
   requires => [ local_admin_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_category_to_group( $user, $group_id, "some_cat1",
            profile => { name => "Category Name 1" }
         );
      })->then( sub {
         matrix_add_category_to_group( $user, $group_id, "some_cat2",
            profile => { name => "Category Name 2" }
         );
      })->then( sub {
         matrix_get_group_categories( $user, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw ( categories ) );
         assert_json_keys( $body->{categories}, qw( some_cat1 some_cat2 ) );

         assert_deeply_eq( $body->{categories}{some_cat1}{profile}, { name => "Category Name 1" } );
         assert_deeply_eq( $body->{categories}{some_cat2}{profile}, { name => "Category Name 2" } );

         Future->done( 1 );
      });
   };


push our @EXPORT, qw( matrix_get_group_category matrix_add_category_to_group matrix_remove_category_from_group matrix_get_group_categories );

sub matrix_get_group_category
{
   my ( $user, $group_id, $category_id ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/unstable/groups/$group_id/categories/$category_id",
   );
}

sub matrix_add_category_to_group
{
   my ( $user, $group_id, $category_id, %opts ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/categories/$category_id",
      content => \%opts,
   );
}

sub matrix_remove_category_from_group
{
   my ( $user, $group_id, $category_id ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/unstable/groups/$group_id/categories/$category_id",
   );
}

sub matrix_get_group_categories
{
   my ( $user, $group_id ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/unstable/groups/$group_id/categories/",
   );
}
