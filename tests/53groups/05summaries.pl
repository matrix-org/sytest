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



sub matrix_add_room_to_group_summary
{
   my ( $user, $group_id, $room_id, %opts ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/groups/$group_id/summary/rooms/$room_id",
      content => \%opts,
   );
}
