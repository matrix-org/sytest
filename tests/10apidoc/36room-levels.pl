test "GET /rooms/:room_id/state/m.room.power_levels can fetch levels",
   requires => [qw( do_request_json user more_users room_id )],

   provides => [qw( can_get_power_levels )],

   check => sub {
      my ( $do_request_json, $user, $more_users, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.power_levels",
      )->then( sub {
         my ( $body ) = @_;

         # Simple level keys
         require_json_keys( $body, qw( ban kick redact state_default events_default users_default ));
         require_json_number( $body->{$_} ) for qw( ban kick redact state_default events_default users_default );

         require_json_object( $body->{events} );

         # Don't care what they keys are
         require_json_number( $_ ) for values %{ $body->{events} };

         require_json_number( $_ ) for values %{ $body->{users} };

         exists $body->{users}{$user->user_id} or
            die "Expected room creator to exist in user powerlevel list";

         $body->{users}{$user->user_id} > $body->{users_default} or
            die "Expected room creator to have a higher-than-default powerlevel";

         provide can_get_power_levels => 1;
         Future->done(1);
      });
   };
