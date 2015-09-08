prepare "Leaving old test room",
   requires => [qw( do_request_json_for local_users room_id
                    can_leave_room )],

   do => sub {
      my ( $do_request_json_for, $users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $do_request_json_for->( $user,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/leave",

            content => {},
         )->else_with_f( sub {
            my ( $f, $failure, $name, $response ) = @_;

            # Ignore 403 forbidden because of not being in the room
            defined $name and $name eq "http" and $response->code == 403 and
               return Future->done();

            return $f;
         });
      } @$users );
   };

unprovide qw( room_id room_alias );
