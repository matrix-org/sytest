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

         any { $room_id eq $_->{room_id} } @{ $body->{rooms_section}{rooms} }
            or die "room not in sumary";

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

         my $rooms = $body->{rooms_section}{rooms};

         my $room1 = first { $room_id1 eq $_->{room_id} } @{ $rooms };
         my $room2 = first { $room_id2 eq $_->{room_id} } @{ $rooms };

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

         any { $room_id eq $_->{room_id} } @{ $body->{rooms_section}{rooms} }
            or die "room not in sumary";

         matrix_remove_room_from_group_summary( $user, $group_id, $room_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );

         any { $room_id eq $_->{room_id} } @{ $body->{rooms_section}{rooms} }
            and die "room still in sumary";

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

         my $rooms = $body->{rooms_section}{rooms};
         my $room = first { $room_id eq $_->{room_id} } @{ $rooms };

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

         any { $room_id eq $_->{room_id} } @{ $body->{rooms_section}{rooms} }
            and die "room still in sumary";

         Future->done( 1 );
      });
   };



test "Add user to group summary",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id );

      matrix_create_group( $user,
         name => "Testing summaries",
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_user_to_group_summary( $user, $group_id, $user->user_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );

         any { $user->user_id eq $_->{user_id} } @{ $body->{users_section}{users} }
            or die "user not in sumary";

         Future->done( 1 );
      });
   };


test "Adding multiple users to group summary have correct order",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id );

      matrix_create_group( $user )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_invite_group_users( $user, $group_id, $viewer );
      })->then( sub {
         matrix_accept_group_invite( $group_id, $viewer );
      })->then( sub {
         matrix_add_user_to_group_summary( $user, $group_id, $user->user_id );
      })->then( sub {
         matrix_add_user_to_group_summary( $user, $group_id, $viewer->user_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );

         log_if_fail "Summary Body", $body;

         my $users = $body->{users_section}{users};

         my $user1 = first { $user->user_id eq $_->{user_id} } @{ $users };
         my $user2 = first { $viewer->user_id eq $_->{user_id} } @{ $users };

         $user1->{order} < $user2->{order} or die "orders are incorrect";

         Future->done( 1 );
      });
   };

test "Remove user from group summary",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id );

      matrix_create_group( $user,
         name => "Testing summaries",
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_user_to_group_summary( $user, $group_id, $user->user_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         any { $user->user_id eq $_->{user_id} } @{ $body->{users_section}{users} }
            or die "user not in sumary";

         matrix_remove_user_from_group_summary( $user, $group_id, $user->user_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         any { $user->user_id eq $_->{user_id} } @{ $body->{users_section}{users} }
            and die "user still in sumary";

         Future->done( 1 );
      });
   };


test "Add user to group summary with role",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user,
         name => "Testing summaries",
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_role_to_group( $user, $group_id, "some_role",
            profile => { name => "Category Name" }
         );
      })->then( sub {
         matrix_add_user_to_group_summary_role( $user, $group_id, "some_role", $user->user_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Summary Body", $body;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );

         my $users = $body->{users_section}{users};
         my $user = first { $user->user_id eq $_->{user_id} } @{ $users };

         assert_json_keys( $user, qw( is_public role_id ) );
         assert_eq( $user->{role_id}, "some_role" );

         assert_json_keys( $body->{users_section}{roles}, qw( some_role ) );

         Future->done( 1 );
      });
   };

test "Remove user from group summary with role",
   requires => [ local_admin_fixture( with_events => 0 ), local_user_fixture( with_events => 0 ) ],

   do => sub {
      my ( $user, $viewer ) = @_;

      my ( $group_id, $room_id );

      matrix_create_group( $user,
         name => "Testing summaries",
      )
      ->then( sub {
         ( $group_id ) = @_;

         matrix_add_role_to_group( $user, $group_id, "some_role",
            profile => { name => "Category Name" }
         );
      })->then( sub {
         matrix_add_user_to_group_summary_role( $user, $group_id, "some_role", $user->user_id );
      })->then( sub {
         matrix_remove_user_from_group_summary_role( $user, $group_id, "some_role", $user->user_id );
      })->then( sub {
         matrix_get_group_summary( $viewer, $group_id );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Summary Body", $body;

         assert_json_keys( $body, qw( profile users_section rooms_section ) );
         assert_eq( $body->{profile}{name}, "Testing summaries" );

         any { $user->user_id eq $_->{user_id} } @{ $body->{users_section}{users} }
            and die "user still in sumary";

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



sub matrix_add_user_to_group_summary
{
   my ( $user, $group_id, $user_id, %opts ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/summary/users/$user_id",
      content => \%opts,
   );
}

sub matrix_add_user_to_group_summary_role
{
   my ( $user, $group_id, $role_id, $user_id, %opts ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/summary/roles/$role_id/users/$user_id",
      content => \%opts,
   );
}

sub matrix_remove_user_from_group_summary_role
{
   my ( $user, $group_id, $role_id, $user_id ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/unstable/groups/$group_id/summary/roles/$role_id/users/$user_id",
   );
}


sub matrix_remove_user_from_group_summary
{
   my ( $user, $group_id, $user_id ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/unstable/groups/$group_id/summary/users/$user_id",
   );
}
