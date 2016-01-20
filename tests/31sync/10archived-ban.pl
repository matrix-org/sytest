test "Banned rooms appear in the leave section of sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id );

      my $filter = { room => { include_leave => JSON::true } };

      Future->needs_all(
         matrix_create_filter( $user_a, $filter ),
         matrix_create_filter( $user_b, $filter ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

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
         assert_json_keys( $room, qw( timeline state ));

         Future->done(1);
      });
   };


test "Newly banned rooms appear in the leave section of incremental sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id );

      my $filter = { room => { include_leave => JSON::true } };

      Future->needs_all(
         matrix_create_filter( $user_a, $filter ),
         matrix_create_filter( $user_b, $filter ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user_b, $room_id);
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         do_request_json_for( $user_a,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/ban",
            content => { user_id => $user_b->user_id, reason => "testing" },
         );
      })->then( sub {
         matrix_sync_again( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         assert_json_keys( $room, qw( timeline state ));

         Future->done(1);
      });
   };


test "Newly banned rooms appear in the leave section of incremental sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id );

      my $filter = { room => { include_leave => JSON::true } };

      Future->needs_all(
         matrix_create_filter( $user_a, $filter ),
         matrix_create_filter( $user_b, $filter ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user_b, $room_id);
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
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
         matrix_sync_again( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{leave}{$room_id};
         assert_json_keys( $room, qw( timeline state ));

         Future->done(1);
      });
   };
