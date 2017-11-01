foreach my $datum (qw( displayname avatar_url )) {
   test "$datum updates affect room member events",
      requires => [ local_user_and_room_fixtures() ],

      do => sub {
         my ( $user, $room_id ) = @_;

         my $uri = "/r0/profile/:user_id/$datum";

         do_request_json_for( $user,
            method => "GET",
            uri    => $uri,
         )->then( sub {
            my ( $body ) = @_;

            if ( $datum eq 'displayname' ) {
               my ( $local_part ) = $user->user_id =~ m/^@([^:]+):/g;
               die ("Expected $datum to be $local_part but was ".$body->{$datum})
                  unless $body->{$datum} eq $local_part;
            }
            else {
               defined $body->{$datum} and die "Didn't expect $datum but was ".$body->{$datum};
            }

            do_request_json_for( $user,
               method  => "PUT",
               uri     => $uri,
               content => {
                  $datum => "LemurLover",
               },
            )
         })->then( sub {
            do_request_json_for( $user,
               method => "GET",
               uri    => "/r0/rooms/$room_id/state/m.room.member/:user_id",
            )
         })->then( sub {
            my ( $body ) = @_;

            assert_eq( $body->{$datum}, "LemurLover", "Room $datum" );

            Future->done( 1 );
         });
      };
}
