test "Add room to group summary",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user,
         name => "Testing summaries",
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_group_rooms( $user, $group_id, $room_id );
      })->then( sub {
         matrix_add_room_to_group_summary( $user, $group_id, $room_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );
         assert_json_keys( $body->{rooms_section}{rooms}, $room_id );

         Future->done( 1 );
      });
   };


test "Adding multiple rooms to group summary have correct order",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id, $room_id1, $room_id2 );

      matrix_create_group( $user,
         name => "Testing summaries",
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id1 ) = @_;

         matrix_add_group_rooms( $user, $group_id, $room_id1 );
      })->then( sub {
         matrix_add_room_to_group_summary( $user, $group_id, $room_id1 );
      })->then( sub {
         matrix_create_room( $user );
      })->then( sub {
         ( $room_id2 ) = @_;

         matrix_add_group_rooms( $user, $group_id, $room_id2 );
      })->then( sub {
         matrix_add_room_to_group_summary( $user, $group_id, $room_id2 );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );

         my $room1 = $body->{rooms_section}{rooms}{$room_id1};
         my $room2 = $body->{rooms_section}{rooms}{$room_id2};

         $room1->{order} < $room2->{order} or die "orders are incorrect";

         Future->done( 1 );
      });
   };

test "Remove room from group summary",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user,
         name => "Testing summaries",
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_group_rooms( $user, $group_id, $room_id );
      })->then( sub {
         matrix_add_room_to_group_summary( $user, $group_id, $room_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );
         assert_json_keys( $body->{rooms_section}{rooms}, $room_id );

         matrix_remove_room_from_group_summary( $user, $group_id, $room_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );

         defined $body->{rooms_section}{rooms}{$room_id}
            and die "room still in summary";

         Future->done( 1 );
      });
   };


test "Add room to group summary with category",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user,
         name => "Testing summaries",
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_group_rooms( $user, $group_id, $room_id );
      })->then( sub {
         matrix_add_category_to_group( $user, $group_id, "some_cat",
            profile => { name => "Category Name" }
         );
      })->then( sub {
         matrix_add_room_to_group_summary_category( $user, $group_id, "some_cat", $room_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Summary Body", $body;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );
         assert_json_keys( $body->{rooms_section}{rooms}, $room_id );

         my $room = $body->{rooms_section}{rooms}{$room_id};

         assert_json_keys( $room, qw( profile is_public category_id ) );
         assert_eq( $room->{category_id}, "some_cat" );

         assert_json_keys( $body->{rooms_section}{categories}, qw( some_cat ) );

         Future->done( 1 );
      });
   };

test "Remove room from group summary with category",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user,
         name => "Testing summaries",
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_group_rooms( $user, $group_id, $room_id );
      })->then( sub {
         matrix_add_category_to_group( $user, $group_id, "some_cat",
            profile => { name => "Category Name" }
         );
      })->then( sub {
         matrix_add_room_to_group_summary_category( $user, $group_id, "some_cat", $room_id );
      })->then( sub {
         matrix_remove_room_from_group_summary_category( $user, $group_id, "some_cat", $room_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Summary Body", $body;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );

         defined $body->{rooms_section}{rooms}{$room_id}
            and die "room still in summary";

         Future->done( 1 );
      });
   };



sub matrix_add_room_to_group_summary
{
   my ( $user, $group_id, $room_id, %opts ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/summary/rooms/$room_id",
      content => \%opts,
   );
}

sub matrix_add_room_to_group_summary_category
{
   my ( $user, $group_id, $category_id, $room_id, %opts ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/summary/categories/$category_id/rooms/$room_id",
      content => \%opts,
   );
}

sub matrix_remove_room_from_group_summary_category
{
   my ( $user, $group_id, $category_id, $room_id, %opts ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/unstable/groups/$group_id/summary/categories/$category_id/rooms/$room_id",
   );
}


sub matrix_remove_room_from_group_summary
{
   my ( $user, $group_id, $room_id ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/unstable/groups/$group_id/summary/rooms/$room_id",
   );
}
