use List::Util qw( first );

# No harm in sharing the users as every test runs in its own room
my $users_preparer = local_users_preparer( 2 );

sub lockeddown_room_preparer
{
   preparer(
      requires => [ $users_preparer, qw( can_change_power_levels ) ],

      do => sub {
         my ( $creator, $test_user ) = @_;

         matrix_create_and_join_room( [ $creator, $test_user ] )
         ->then( sub {
            my ( $room_id ) = @_;

            matrix_change_room_powerlevels( $creator, $room_id, sub {
               my ( $levels ) = @_;

               # Allow users at 80 or above to edit any of the room state
               $_ > 80 and $_ = 80 for values %{ $levels->{events} };
            })->then_done( $room_id );
         });
      },
   );
}

sub test_powerlevel
{
   my ( $name, %args ) = @_;

   my $try = $args{try};
   my @requires = @{ $args{requires} };

   multi_test $name,
      requires => [ $users_preparer, lockeddown_room_preparer(),
                    qw( can_change_power_levels ),
                    @requires ],

      do => sub {
         my ( $creator, $test_user, $room_id ) = @_;

         # Fails at powerlevel 0
         matrix_change_room_powerlevels( $creator, $room_id, sub {
            my ( $levels ) = @_;
            $levels->{users}{ $test_user->user_id } = 0;
         })->then( sub {
            $try->( $test_user, $room_id )
               ->main::expect_http_403
         })->then( sub {
            pass( "Fails at powerlevel 0" );

            # Succeeds at powerlevel 80
            matrix_change_room_powerlevels( $creator, $room_id, sub {
               my ( $levels ) = @_;
               $levels->{users}{ $test_user->user_id } = 80;
            })
         })->then( sub {
            $try->( $test_user, $room_id );
         })->on_done( sub {
            pass( "Succeeds at powerlevel 100" );
         })
      };
}

test_powerlevel "'ban' event respects room powerlevel",
   requires => [qw( can_ban_room )],

   try => sub {
      my ( $test_user, $room_id ) = @_;

      do_request_json_for( $test_user,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/ban",

         content => { user_id => '@random_dude:test', reason => "testing" },
      );
   };

# Currently there's no way to limit permission on invites
## test_powerlevel "'invite' event respects room powerlevel",
##    requires => [qw( test_user
##                     can_invite_room )],
## 
##    try => sub {
##       my ( $test_user, $room_id ) = @_;
## 
##       matrix_invite_user_to_room( $test_user, '@random-invitee:localhost:8001', $room_id );
##    };

test_powerlevel "setting 'm.room.name' respects room powerlevel",
   requires => [qw( can_set_room_name )],

   try => sub {
      my ( $test_user, $room_id ) = @_;

      matrix_put_room_state( $test_user, $room_id,
         type    => "m.room.name",
         content => { name => "A new room name" },
      );
   };

test_powerlevel "setting 'm.room.power_levels' respects room powerlevel",
   requires => [qw( can_change_power_levels )],

   try => sub {
      my ( $test_user, $room_id ) = @_;

      matrix_change_room_powerlevels( $test_user, $room_id, sub {
         my ( $levels ) = @_;
         $levels->{users}{'@some-random-user:here'} = 50;
      });
   };

test "Unprivileged users can set m.room.topic if it only needs level 0",
   requires => [ $users_preparer, lockeddown_room_preparer(),
                 qw( can_change_power_levels )],

   do => sub {
      my ( $creator, $test_user, $room_id ) = @_;

      matrix_change_room_powerlevels( $creator, $room_id, sub {
         my ( $levels ) = @_;
         delete $levels->{users}{ $test_user->user_id };
         $levels->{events}{"m.room.topic"} = 0;
      })->then( sub {
         matrix_put_room_state( $test_user, $room_id,
            type    => "m.room.topic",
            content => { topic => "Here I can set the topic at powerlevel 0" },
         );
      });
   };

foreach my $levelname (qw( ban kick redact )) {
   multi_test "Users cannot set $levelname powerlevel higher than their own",
      requires => [ $users_preparer, lockeddown_room_preparer(),
                    qw( can_change_power_levels )],

      do => sub {
         my ( $user, undef, $room_id ) = @_;

         matrix_change_room_powerlevels( $user, $room_id, sub {
            my ( $levels ) = @_;

            $levels->{$levelname} = 25;
         })->SyTest::pass_on_done( "Succeeds at setting 25" )
         ->then( sub {
            matrix_change_room_powerlevels( $user, $room_id, sub {
               my ( $levels ) = @_;

               $levels->{$levelname} = 10000000;
            })->main::expect_http_403
         })->SyTest::pass_on_done( "Fails at setting 75" );
      };
}
