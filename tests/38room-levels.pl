use List::Util qw( max );

my $set_user_powerlevel = sub {
   my ( $do_request_json_for, $opuser, $room_id, $user_id, $level ) = @_;

   $do_request_json_for->( $opuser,
      method => "GET",
      uri    => "/rooms/$room_id/state/m.room.power_levels",
   )->then( sub {
      my ( $levels ) = @_;

      $levels->{users}{ $user_id } = $level;

      $do_request_json_for->( $opuser,
         method => "PUT",
         uri    => "/rooms/$room_id/state/m.room.power_levels",

         content => $levels,
      );
   })
};

multi_test "'ban' event respects room powerlevel",
   requires => [qw( do_request_json_for user local_users room_id
                    can_ban_room )],

   do => sub {
      my ( $do_request_json_for, $user, $local_users, $room_id ) = @_;
      my $test_user = $local_users->[1];

      # Fails at powerlevel 0
      $set_user_powerlevel->( $do_request_json_for, $user, $room_id,
         $test_user->user_id, 0
      )->then( sub {
         $do_request_json_for->( $test_user,
            method => "POST",
            uri    => "/rooms/$room_id/ban",

            content => { user_id => '@random_dude:test', reason => "testing" },
         )->then(
            sub { # done
               Future->fail( "Expected to fail at powerlevel=0 but it didn't" );
            },
            sub { # fail
               my ( $message, $name, $response, $request ) = @_;
               $name eq "http" and $response and $response->code == 403 and
                  return Future->done;

               return Future->fail( @_ );
            },
         )
      })->then( sub {
         pass( "Fails at powerlevel 0" );

         # Succeeds at powerlevel 100
         $set_user_powerlevel->( $do_request_json_for, $user, $room_id,
            $test_user->user_id, 100
         )
      })->then( sub {
         $do_request_json_for->( $test_user,
            method => "POST",
            uri    => "/rooms/$room_id/ban",

            content => { user_id => '@random_dude:test', reason => "testing" },
         );
      })->on_done( sub {
         pass( "Succeeds at powerlevel 100" );
      })
   };
