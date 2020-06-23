test "AS user (not ghost) can join room without registering",
   requires => [ $main::AS_USER[0], local_user_fixture(), $main::HOMESERVER_INFO[0] ],

   do => sub {
      my ( $as_user, $user, $hs_info ) = @_;

      my $room_id;

      matrix_create_room( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_invite_user_to_room( $user, $as_user, $room_id )
      })->then( sub {
         matrix_join_room( $as_user, $room_id )
      });
   };

# TODO: Remove this test when the in-use ASes stop passing the user_id param
# (or if we end up killing non-ghost AS users)
test "AS user (not ghost) can join room without registering, with user_id query param",
   requires => [ $main::AS_USER[0], local_user_fixture() ],

   do => sub {
      my ( $as_user, $user ) = @_;

      my $room_id;

      matrix_create_room( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_invite_user_to_room( $user, $as_user, $room_id )
      })->then( sub {
         do_request_json_for( $as_user,
            method => "POST",
            uri    => "/r0/join/$room_id",

            params => {
               user_id => $as_user->user_id,
            },
            content => {},
         );
      });
   };
