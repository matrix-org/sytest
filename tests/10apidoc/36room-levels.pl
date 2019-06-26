my ( $user_fixture, $room_fixture ) = local_user_and_room_fixtures();

test "GET /rooms/:room_id/state/m.room.power_levels can fetch levels",
   requires => [ $user_fixture, $room_fixture ],

   proves => [qw( can_get_power_levels )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/rooms/$room_id/state/m.room.power_levels",
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
            uri    => "/r0/rooms/$room_id/state/m.room.power_levels",
            content => $levels,
         )
      })->then( sub {
         retry_until_success {
            matrix_get_room_state( $user, $room_id, type => "m.room.power_levels" )
         }
      })->then( sub {
         my ( $levels ) = @_;

         $levels->{users}{'@random-other-user:their.home'} == 20 or
            die "Expected to have set other user's level to 20";

         Future->done(1);
      });
   };

test "PUT power_levels should not explode if the old power levels were empty",
   requires => [ $user_fixture, $room_fixture,
                 qw( can_get_power_levels )],

   do => sub {
      my ( $user, $room_id ) = @_;

      # absence of an 'events' key
      matrix_put_room_state(
         $user,
         $room_id,
         type      => "m.room.power_levels",
         state_key => "",
         content   => {
            users => {
               $user->user_id => 100,
            },
         },
      )->then( sub {
         # absence of a 'users' key
         matrix_put_room_state(
            $user,
            $room_id,
            type      => "m.room.power_levels",
            state_key => "",
            content   => {
            },
         );
      })->then( sub {
         # this should now give a 403 (not a 500)
         matrix_put_room_state(
            $user,
            $room_id,
            type      => "m.room.power_levels",
            state_key => "",
            content   => {
               users => {},
            },
         ) -> main::expect_http_403;
      })->then( sub {
         matrix_get_room_state( $user, $room_id, type => "m.room.power_levels" )
      });
   };


test "Both GET and PUT work",
   requires => [qw( can_get_power_levels can_set_power_levels )],

   proves => [qw( can_change_power_levels )],

   check => sub {
      # Nothing to be done

      Future->done(1);
   };

push our @EXPORT, qw( matrix_change_room_power_levels );

sub matrix_change_room_power_levels
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
