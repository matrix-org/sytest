push our @EXPORT, qw( matrix_add_tag matrix_remove_tag );

=head2 matrix_add_tag

   matrix_add_tag($user, $room_id, $tag)->get;

Add a tag to the room for the user.

=cut

sub matrix_add_tag
{
   my ( $user, $room_id, $tag, $content ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/user/:user_id/rooms/$room_id/tags/$tag",
      content => $content
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
      uri     => "/r0/user/:user_id/rooms/$room_id/tags/$tag",
      content => {}
   );
}
