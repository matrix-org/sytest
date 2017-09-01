test "/joined_rooms returns only joined rooms",
   requires => [ local_user_fixture(), local_user_fixture(),
                 qw( can_get_joined_rooms ) ],

   do => sub {
      my ( $user, $inviter ) = @_;

      # Create three rooms; one joined, one joined-then-left, one only invited
      my ( $room_joined, $room_left, $room_invited );

      Future->needs_all(
         matrix_create_room( $user )->on_done( sub {
            ( $room_joined ) = @_;
            log_if_fail "room joined", $room_joined;
         }),

         matrix_create_room( $user )->then( sub {
            ( $room_left ) = @_;
            log_if_fail "room left", $room_left;

            matrix_leave_room( $user, $room_left );
         }),

         matrix_create_room( $inviter )->then( sub {
            ( $room_invited ) = @_;
            log_if_fail "room invited", $room_invited;

            matrix_invite_user_to_room( $inviter, $user, $room_invited );
         }),
      )->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri => "/unstable/joined_rooms",
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( joined_rooms ) );
         assert_json_list( my $joined_rooms = $body->{joined_rooms} );

         # Only $room_joined should appear

         assert_eq( scalar @$joined_rooms, 1, "1 room returned" );
         assert_eq( $joined_rooms->[0], $room_joined, "joined_rooms[0]" );

         Future->done(1);
      });
   };


my $display_name = "Display Name";
my $avatar_url = "http://example.com/avatar.png";

test "/joined_members return joined members",
   requires => [
      local_user_fixture(
         displayname => $display_name,
         avatar_url  => $avatar_url
      ),
      local_user_fixtures( 3 ),
      qw( can_get_room_joined_members )
   ],

   do => sub {
      my ( $creator, $user_joined, $user_left, $user_invited ) = @_;
      # Three users; one joined, one joined-then-left, one only invited

      my $room_id;

      matrix_create_room( $creator,
         invite => [ $user_joined->user_id, $user_left->user_id, $user_invited->user_id ],
      )->then( sub {
         ( $room_id ) = @_;

         log_if_fail "room", $room_id;

         Future->needs_all(
            matrix_join_room( $user_joined, $room_id ),

            matrix_join_room( $user_left, $room_id )->then( sub {
               matrix_leave_room( $user_left, $room_id );
            }),
         );
      })->then( sub {
         # Test /rooms/:room_id/joined_members as both current room members
         my @users = ( $creator, $user_joined );

         Future->needs_all( map {
            my $user = $_;

            do_request_json_for( $user,
               method => "GET",
               uri => "/unstable/rooms/$room_id/joined_members",
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "Body", $body;

               assert_json_keys( $body, qw( joined ));
               assert_json_object( my $members = $body->{joined} );

               assert_deeply_eq( $members, {
                  $creator->user_id => {
                     display_name => $display_name,
                     avatar_url   => $avatar_url,
                  },
                  $user_joined->user_id => {
                     display_name => undef,
                     avatar_url   => undef,
                  },
               } );

               Future->done(1);
            });
         } @users );
      })
   };
