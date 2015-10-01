prepare "Leaving old test room",
   requires => [qw( local_users room_id )],

   do => sub {
      my ( $users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         matrix_leave_room( $user, $room_id )
         ->else_with_f( sub {
            my ( $f, $failure, $name, $response ) = @_;

            # Ignore 403 forbidden because of not being in the room
            defined $name and $name eq "http" and $response->code == 403 and
               return Future->done();

            return $f;
         });
      } @$users );
   };

unprovide qw( room_id room_alias );
