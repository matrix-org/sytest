push our @EXPORT, qw( matrix_add_account_data matrix_add_room_account_data );

=head2 matrix_add_account_data

   matrix_add_account_data( $user, $type, $content )->get;

Add account data for the user.

=cut

sub matrix_add_account_data
{
   my ( $user, $type, $content ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/user/:user_id/account_data/$type",
      content => $content
   );
}

=head2 matrix_add_room_account_data

    matrix_add_account_data( $user, $room_id, $type, $content )->get;

Add account data for the user for a room.

=cut

sub matrix_add_room_account_data
{
   my ( $user, $room_id, $type, $content ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/user/:user_id/rooms/$room_id/account_data/$type",
      content => $content
   );
}
