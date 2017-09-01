use List::Util qw( first );

test "Rooms a user is invited to appear in an initial sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id );

      Future->needs_all(
         matrix_create_filter( $user_a, {} ),
         matrix_create_filter( $user_b, {} ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_invite_user_to_room_synced(
            $user_a, $user_b, $room_id
         );
      })->then( sub {
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{invite}{$room_id};
         assert_json_keys( $room, qw( invite_state ) );
         assert_json_keys( $room->{invite_state}, qw( events ) );

         my $invite = first {
            $_->{type} eq "m.room.member"
               and $_->{state_key} eq $user_b->user_id
         } @{ $room->{invite_state}{events} };

         assert_json_keys( $invite, qw( sender content state_key type ));
         $invite->{content}{membership} eq "invite"
            or die "Expected an invite event";
         $invite->{sender} eq $user_a->user_id
            or die "Expected the invite to be from user A";

         Future->done(1);
      })
   };


test "Rooms a user is invited to appear in an incremental sync",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b, $room_id );

      Future->needs_all(
         matrix_create_filter( $user_a, {} ),
         matrix_create_filter( $user_b, {} ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         matrix_create_room( $user_a );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_invite_user_to_room_synced(
            $user_a, $user_b, $room_id
         );
      })->then( sub {
         matrix_sync_again( $user_b, filter => $filter_id_b );
      })->then( sub {
         my ( $body ) = @_;
         my $room = $body->{rooms}{invite}{$room_id};
         assert_json_keys( $room, qw( invite_state ) );
         assert_json_keys( $room->{invite_state}, qw( events ) );

         my $invite = first {
            $_->{type} eq "m.room.member"
               and $_->{state_key} eq $user_b->user_id
         } @{ $room->{invite_state}{events} };

         assert_json_keys( $invite, qw( sender content state_key type ));
         $invite->{content}{membership} eq "invite"
            or die "Expected an invite event";
         $invite->{sender} eq $user_a->user_id
            or die "Expected the invite to be from user A";

         Future->done(1);
      })
   };
