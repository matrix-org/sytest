foreach my $datum (qw( displayname avatar_url )) {
   test "$datum updates affect room member events",
      requires => [ local_user_and_room_fixtures() ],

      do => sub {
         my ( $user, $room_id ) = @_;

         my $uri = "/v3/profile/:user_id/$datum";

         do_request_json_for( $user,
            method => "GET",
            uri    => $uri,
         )->then( sub {
            my ( $body ) = @_;

            # N.B. nowadays we let servers specify default displayname & avatar_url
            # previously we asserted that these must be undefined at this point.

            do_request_json_for( $user,
               method  => "PUT",
               uri     => $uri,
               content => {
                  $datum => "LemurLover",
               },
            )
         })->then( sub {
             await_sync_timeline_or_state_contains( $user, $room_id, check => sub {
               my ( $event ) = @_;

               return unless $event->{type} eq "m.room.member";
               return unless $event->{state_key} eq $user->user_id;
               return unless $event->{content}->{$datum} eq "LemurLover";

               return 1;
            });
         })->then( sub {
            do_request_json_for( $user,
               method => "GET",
               uri    => "/v3/rooms/$room_id/state/m.room.member/:user_id",
            )
         })->then( sub {
            my ( $body ) = @_;

            assert_eq( $body->{$datum}, "LemurLover", "Room $datum" );

            Future->done( 1 );
         });
      };
}
