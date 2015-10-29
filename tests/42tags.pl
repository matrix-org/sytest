push our @EXPORT, qw( matrix_add_tag );

=head2 matrix_add_tag

   matrix_add_tag($user, $room_id, $tag)->get;

Add a tag to the room for the user.

=cut

sub matrix_add_tag
{
   my ( $user, $room_id, $tag ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/v2_alpha/user/:user_id/rooms/$room_id/tags/$tag",
      content => {}
   );
}


=head2 matrix_remove_tag

    matrix_remove_tag( $user, $room_id, $tag )->get;

Remove a tag from the room for the user.

=cut

sub matrix_remove_tag
{
   my ( $user, $room_id, $tag ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/v2_alpha/user/:user_id/rooms/$room_id/tags/$tag",
      content => {}
   );
}


=head2 matrix_list_tags

    my $tags = matrix_list_tags( $user, $room_id )->get;

List the tags on the room for the user.

=cut

sub matrix_list_tags
{
   my ( $user, $room_id ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/v2_alpha/user/:user_id/rooms/$room_id/tags",
      content => {}
   )->then( sub {
      my ( $body ) = @_;

      require_json_keys( $body, qw( tags ) );

      Future->done( $body->{tags} );
   });
}


test "Can add tag",
   requires => [qw( first_api_client )],

   provides => [qw( can_add_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );

      matrix_register_user( $http, undef, with_events => 0 )->then( sub {
         ( $user ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_tag( $user, $room_id, "test_tag" );
      })->on_done( sub {
         provide can_add_tag => 1
      });
   };


test "Can remove tag",
   requires => [qw( first_api_client )],

   provides => [qw( can_remove_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );

      matrix_register_user( $http, undef, with_events => 0 )->then( sub {
         ( $user ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_remove_tag( $user, $room_id, "test_tag" );
      })->on_done( sub {
         provide can_remove_tag => 1
      });
   };


test "Can list tags for a room",
   requires => [qw( first_api_client can_add_tag can_remove_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );

      matrix_register_user( $http, undef, with_events => 0 )->then( sub {
         ( $user ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_tag( $user, $room_id, "test_tag" );
      })->then( sub {
         matrix_list_tags( $user, $room_id );
      })->then( sub {
         my ( $tags ) = @_;

         @{ $tags } == 1 or die "Expected one tag for the room";
         $tags->[0] eq "test_tag" or die "Unexpected tag";

         matrix_remove_tag( $user, $room_id, "test_tag" );
      })->then( sub {
         matrix_list_tags( $user, $room_id );
      })->then( sub {
         my ( $tags ) = @_;

         @{ $tags } == 0 or die "Expected no tags for the room";

         Future->done(1);
      });
   };


test "Tags appear in the v1 /events stream",
   requires => [qw( first_api_client can_add_tag can_remove_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );

      matrix_register_user( $http, undef )->then( sub {
         ( $user ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_tag( $user, $room_id, "test_tag");
      })->then( sub {
         await_event_for( $user, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.tag"
               and $event->{room_id} eq $room_id
               and $event->{content}{tags}[0] eq "test_tag";
            return 1;
         });
      });
   };
