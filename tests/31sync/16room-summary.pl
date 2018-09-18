use Future::Utils qw( repeat );

test "Unnamed room comes with a name summary",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_join_room_synced( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail ( "sync response:", $body->{rooms}{join}{$room_id} );
         my $summary = $body->{rooms}{join}{$room_id}{summary};
         assert_deeply_eq( $summary, {
            'm.joined_member_count' => 3,
            'm.invited_member_count' => 0,
            'm.heroes' => [
               $bob->user_id,
               $charlie->user_id,
            ]
         });
         Future->done(1);
      });
   };

test "Named room with avatar comes with just joined member count summary",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state_synced( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_put_room_state_synced( $alice, $room_id,
            type    => "m.room.avatar",
            content => { url => "mxc://example.com/something" },
         );
      })->then( sub {
         matrix_join_room_synced( $bob, $room_id );
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail ( "sync response:", $body->{rooms}{join}{$room_id} );
         my $summary = $body->{rooms}{join}{$room_id}{summary};
         assert_deeply_eq($summary, {
            'm.joined_member_count' => 3,
            'm.invited_member_count' => 0,
         });
         Future->done(1);
      });
   };

test "Room summary only has 5 heroes",
   requires => [ local_user_fixtures( 6 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, @users ) = @_;

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         repeat( sub {
            matrix_join_room_synced( $_[0], $room_id );
         }, foreach => [ @users ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail ( "sync response:", $body->{rooms}{join}{$room_id} );
         my $summary = $body->{rooms}{join}{$room_id}{summary};
         my $expected_heroes = [
            (sort( map { $_->user_id } @users ))[0..4]
         ];
         log_if_fail( "expected_heroes:", $expected_heroes );
         assert_deeply_eq($summary, {
            'm.joined_member_count' => 6,
            'm.invited_member_count' => 0,
            'm.heroes' => $expected_heroes,
         });
         Future->done(1);
      });
   };

test "Room summary counts change when membership changes",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      my ( $filter_id, $room_id );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
         }
      })->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_put_room_state_synced( $alice, $room_id,
            type    => "m.room.name",
            content => { name => "A room name" },
         );
      })->then( sub {
         matrix_put_room_state_synced( $alice, $room_id,
            type    => "m.room.avatar",
            content => { url => "mxc://example.com/something" },
         );
      })->then( sub {
         matrix_join_room_synced( $bob, $room_id );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail ( "sync response:", $body->{rooms}{join}{$room_id} );
         my $summary = $body->{rooms}{join}{$room_id}{summary};
         assert_deeply_eq($summary, {
            'm.joined_member_count' => 2,
            'm.invited_member_count' => 0,
         });

         matrix_join_room_synced( $charlie, $room_id );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail ( "sync response:", $body->{rooms}{join}{$room_id} );
         my $summary = $body->{rooms}{join}{$room_id}{summary};
         assert_deeply_eq($summary, {
            'm.joined_member_count' => 3,
            'm.invited_member_count' => 0,
         });

         matrix_leave_room_synced( $bob, $room_id );
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;
         log_if_fail ( "sync response:", $body->{rooms}{join}{$room_id} );
         my $summary = $body->{rooms}{join}{$room_id}{summary};
         assert_deeply_eq($summary, {
            'm.joined_member_count' => 2,
            'm.invited_member_count' => 0,
         });
         Future->done(1);
      });
   };

# TODO: test that parted users don't feature in room summaries, unless everyone has left
# TODO: check we receive room state for unknown hero mxids
# TODO: check that room summary changes whenever membership changes
