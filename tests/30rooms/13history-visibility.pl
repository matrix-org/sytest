push our @EXPORT, qw( matrix_set_room_history_visibility );

sub matrix_set_room_history_visibility
{
   my ( $user, $room_id, $history_visibility ) = @_;

   matrix_put_room_state( $user, $room_id,
      type    => "m.room.history_visibility",
      content => { history_visibility => $history_visibility }
   );
}
