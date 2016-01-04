my ( $user_fixture, $room_fixture ) = local_user_and_room_fixtures();

test "GET /rooms/:room_id/state/m.room.power_levels can fetch levels",
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_get_power_levels )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.power_levels",
      )->then( sub {
         my ( $body ) = @_;

         # Simple level keys
         assert_json_keys( $body, qw( ban kick redact state_default events_default users_default ));
         assert_json_number( $body->{$_} ) for qw( ban kick redact state_default events_default users_default );

         assert_json_object( $body->{events} );

         # Don't care what they keys are
         assert_json_number( $_ ) for values %{ $body->{events} };

         assert_json_number( $_ ) for values %{ $body->{users} };

         exists $body->{users}{ $user->user_id } or
            die "Expected room creator to exist in user powerlevel list";

         $body->{users}{ $user->user_id } > $body->{users_default} or
            die "Expected room creator to have a higher-than-default powerlevel";

         Future->done(1);
      });
   };

test "PUT /rooms/:room_id/state/m.room.power_levels can set levels",
   requires => [ $user_fixture, $room_fixture,
                 qw( can_get_power_levels )],

   proves => [qw( can_set_power_levels )],

   do => sub {
      my ( $user, $room_id ) = @_;

      matrix_get_room_state( $user, $room_id, type => "m.room.power_levels" )
      ->then( sub {
         my ( $levels ) = @_;

         $levels->{users}{'@random-other-user:their.home'} = 20;

         do_request_json_for( $user,
            method => "PUT",
            uri    => "/api/v1/rooms/$room_id/state/m.room.power_levels",
            content => $levels,
         )
      })->then( sub {
         matrix_get_room_state( $user, $room_id, type => "m.room.power_levels" )
      })->then( sub {
         my ( $levels ) = @_;

         $levels->{users}{'@random-other-user:their.home'} == 20 or
            die "Expected to have set other user's level to 20";

         Future->done(1);
      });
   };

test "Both GET and PUT work",
   requires => [qw( can_get_power_levels can_set_power_levels )],

   proves => [qw( can_change_power_levels )],

   check => sub {
      # Nothing to be done

      Future->done(1);
   };

push our @EXPORT, qw( matrix_change_room_powerlevels );

sub matrix_change_room_powerlevels
{
   my ( $user, $room_id, $func ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   matrix_get_room_state( $user, $room_id, type => "m.room.power_levels" )
   ->then( sub {
      my ( $levels ) = @_;
      $func->( $levels );

      matrix_put_room_state( $user, $room_id, type => "m.room.power_levels",
         content => $levels,
      );
   });
}
