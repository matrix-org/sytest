# Tests migrated to Complement as of https://github.com/matrix-org/complement/pull/545
# However this helper function is used in other tests.

push our @EXPORT, qw( matrix_change_room_power_levels );

sub matrix_change_room_power_levels
{
   my ( $user, $room_id, $func ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   matrix_get_room_state( $user, $room_id, type => "m.room.power_levels" )
   ->then( sub {
      my ( $levels ) = @_;
      $func->( $levels );

      matrix_put_room_state_synced( $user, $room_id, type => "m.room.power_levels",
         content => $levels,
      );
   });
}
