multi_test "Non-present room members cannot ban others",
   requires => [qw( make_test_room do_request_json_for change_room_powerlevels local_users
                    can_ban_room )],

   do => sub {
      my ( $make_test_room, $do_request_json_for, $change_room_powerlevels, $local_users ) = @_;
      my $creator = $local_users->[0];
      my $testuser = $local_users->[1];

      my $room_id;

      $make_test_room->( $creator )->then( sub {
         ( $room_id ) = @_;

         pass "Created room";

         $change_room_powerlevels->( $creator, $room_id, sub {
            my ( $levels ) = @_;
            $levels->{users}{ $testuser->user_id } = 100;
         })
      })->then( sub {
         pass "Set powerlevel";

         $do_request_json_for->( $testuser,
            method => "POST",
            uri    => "/rooms/$room_id/ban",

            content => { user_id => '@random_dude:test', reason => "testing" },
         )->then(
            sub { # done
               Future->fail( "Expected not to succeed but it did" );
            },
            sub { # fail
               my ( $message, $name, $response ) = @_;
               $name and $name eq "http" and $response and $response->code == 403 and
                  return Future->done;
               Future->fail( @_ );
            }
         )
      })->then( sub {
         pass "Attempt to ban is rejected";

         Future->done(1);
      });
   };
