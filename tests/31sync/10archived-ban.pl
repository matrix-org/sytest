test "Banned rooms appear in the leave section of sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id );

      Future->needs_all(
         matrix_register_user_with_filter( $http, {} ),
         matrix_register_user_with_filter( $http, {} ),
      )->then( sub {
         ( $user_a, $filter_id_a, $user_b, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user_b, $room_id);
      })->then( sub {

         do_request_json_for( $user_a,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/ban",
            content => { user_id => $user_b->user_id, reason => "testing" },
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ));

         Future->done(1);
      });
   };


test "Newly banned rooms appear in the leave section of incremental sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id, $next_b );

      Future->needs_all(
         matrix_register_user_with_filter( $http, {} ),
         matrix_register_user_with_filter( $http, {} ),
      )->then( sub {
         ( $user_a, $filter_id_a, $user_b, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user_b, $room_id);
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         $next_b = $body->{next_batch};

         do_request_json_for( $user_a,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/ban",
            content => { user_id => $user_b->user_id, reason => "testing" },
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b, since => $next_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ));

         Future->done(1);
      });
   };


test "Newly banned rooms appear in the leave section of incremental sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user_a, $filter_id_a, $user_b, $filter_id_b, $room_id, $next_b );

      Future->needs_all(
         matrix_register_user_with_filter( $http, {} ),
         matrix_register_user_with_filter( $http, {} ),
      )->then( sub {
         ( $user_a, $filter_id_a, $user_b, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user_b, $room_id);
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         $next_b = $body->{next_batch};

         do_request_json_for( $user_a,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/ban",
            content => { user_id => $user_b->user_id, reason => "testing" },
         );
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_message( $user_a, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 20 );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b, since => $next_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         require_json_keys( $room, qw( event_map timeline state ));

         Future->done(1);
      });
   };
