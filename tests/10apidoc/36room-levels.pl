test "GET /rooms/:room_id/state/m.room.power_levels can fetch levels",
   requires => [qw( do_request_json user room_id )],

   provides => [qw( can_get_power_levels )],

   check => sub {
      my ( $do_request_json, $user, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.power_levels",
      )->then( sub {
         my ( $body ) = @_;

         # Simple level keys
         require_json_keys( $body, qw( ban kick redact state_default events_default users_default ));
         require_json_number( $body->{$_} ) for qw( ban kick redact state_default events_default users_default );

         require_json_object( $body->{events} );

         # Don't care what they keys are
         require_json_number( $_ ) for values %{ $body->{events} };

         require_json_number( $_ ) for values %{ $body->{users} };

         exists $body->{users}{ $user->user_id } or
            die "Expected room creator to exist in user powerlevel list";

         $body->{users}{ $user->user_id } > $body->{users_default} or
            die "Expected room creator to have a higher-than-default powerlevel";

         provide can_get_power_levels => 1;
         Future->done(1);
      });
   };

test "PUT /rooms/:room_id/state/m.room.power_levels can set levels",
   requires => [qw( do_request_json user more_users room_id
                    can_get_power_levels )],

   provides => [qw( can_set_power_levels )],

   do => sub {
      my ( $do_request_json, $user, $more_users, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.power_levels",
      )->then( sub {
         my ( $levels ) = @_;

         $levels->{users}{'@random-other-user:their.home'} = 20;

         $do_request_json->(
            method => "PUT",
            uri    => "/api/v1/rooms/$room_id/state/m.room.power_levels",
            content => $levels,
         )
      })->then( sub {
         $do_request_json->(
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state/m.room.power_levels",
         )
      })->then( sub {
         my ( $levels ) = @_;

         $levels->{users}{'@random-other-user:their.home'} == 20 or
            die "Expected to have set other user's level to 20";

         provide can_set_power_levels => 1;
         Future->done(1);
      });
   };

prepare "Creating power_level change helper",
   requires => [qw( do_request_json_for
                    can_get_power_levels can_set_power_levels )],

   provides => [qw( change_room_powerlevels )],

   do => sub {
      my ( $do_request_json_for ) = @_;

      provide change_room_powerlevels => sub {
         my ( $user, $room_id, $func ) = @_;

         $do_request_json_for->( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state/m.room.power_levels",
         )->then( sub {
            my ( $levels ) = @_;
            $func->( $levels );

            $do_request_json_for->( $user,
               method => "PUT",
               uri    => "/api/v1/rooms/$room_id/state/m.room.power_levels",

               content => $levels,
            );
         });
      };

      Future->done(1);
   };
