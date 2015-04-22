use List::Util qw( first );

my $room_id;

prepare "Creating a new test room",
   requires => [qw( make_test_room local_users )],

   do => sub {
      my ( $make_test_room, $local_users ) = @_;
      my $creator   = $local_users->[0];
      my $test_user = $local_users->[1];

      $make_test_room->( $creator, $test_user )
         ->on_done( sub {
            ( $room_id ) = @_;
         });
   };

my $EXPECT_HTTP_403 = sub {
   my ( $f ) = @_;
   $f->then(
      sub { # done
         Future->fail( "Expected to receive an HTTP 403 failure but it succeeded" )
      },
      sub { # fail
         my ( undef, $name, $response ) = @_;
         $name and $name eq "http" and $response and $response->code == 403 and
            return Future->done;
         Future->fail( @_ );
      },
   );
};

sub test_powerlevel
{
   my ( $name, %args ) = @_;

   my $do = $args{do};
   my @requires = @{ $args{requires} };

   my $test_user_idx = first { $requires[$_] eq "test_user" } 0 .. $#requires;
   if( defined $test_user_idx ) {
      splice @requires, $test_user_idx, 1, ();
   }

   multi_test $name,
      requires => [qw( do_request_json_for change_room_powerlevels user local_users ),
                   @requires ],

      do => sub {
         my ( $do_request_json_for, $change_room_powerlevels, $user, $local_users,
              @dependencies ) = @_;
         my $test_user = $local_users->[1];

         if( defined $test_user_idx ) {
            splice @dependencies, $test_user_idx, 0, ( $test_user );
         }

         # Fails at powerlevel 0
         $change_room_powerlevels->( $user, $room_id, sub {
            my ( $levels ) = @_;
            $levels->{users}{ $test_user->user_id } = 0;
         })->then( sub {
            $do->( @dependencies )
               ->$EXPECT_HTTP_403
         })->then( sub {
            pass( "Fails at powerlevel 0" );

            # Succeeds at powerlevel 100
            $change_room_powerlevels->( $user, $room_id, sub {
               my ( $levels ) = @_;
               $levels->{users}{ $test_user->user_id } = 100;
            })
         })->then( sub {
            $do->( @dependencies );
         })->on_done( sub {
            pass( "Succeeds at powerlevel 100" );
         })
      };
}

test_powerlevel "'ban' event respects room powerlevel",
   requires => [qw( do_request_json_for test_user
                    can_ban_room )],

   do => sub {
      my ( $do_request_json_for, $test_user ) = @_;

      $do_request_json_for->( $test_user,
         method => "POST",
         uri    => "/rooms/$room_id/ban",

         content => { user_id => '@random_dude:test', reason => "testing" },
      );
   };

# Currently there's no way to limit permission on invites
## test_powerlevel "'invite' event respects room powerlevel",
##    requires => [qw( do_request_json_for test_user
##                     can_invite_room )],
## 
##    do => sub {
##       my ( $do_request_json_for, $test_user ) = @_;
## 
##       $do_request_json_for->( $test_user,
##          method => "POST",
##          uri    => "/rooms/$room_id/invite",
## 
##          content => { user_id => '@random-invitee:localhost:8001' },
##       );
##    };

test_powerlevel "setting 'm.room.name' respects room powerlevel",
   requires => [qw( do_request_json_for test_user
                    can_set_room_name )],

   do => sub {
      my ( $do_request_json_for, $test_user ) = @_;

      $do_request_json_for->( $test_user,
         method => "PUT",
         uri    => "/rooms/$room_id/state/m.room.name",

         content => { name => "A new room name" },
      );
   };

test_powerlevel "setting 'm.room.power_levels' respects room powerlevel",
   requires => [qw( change_room_powerlevels test_user
                    can_get_power_levels )],

   do => sub {
      my ( $change_room_powerlevels, $test_user ) = @_;

      $change_room_powerlevels->( $test_user, $room_id, sub {
         my ( $levels ) = @_;
         $levels->{users}{'@some-random-user:here'} = 50;
      });
   };

test "Unprivileged users can set m.room.topic if it only needs level 0",
   requires => [qw( do_request_json_for change_room_powerlevels local_users )],

   do => sub {
      my ( $do_request_json_for, $change_room_powerlevels, $local_users ) = @_;
      my $creator = $local_users->[0];
      my $test_user = $local_users->[1];

      $change_room_powerlevels->( $creator, $room_id, sub {
         my ( $levels ) = @_;
         delete $levels->{users}{ $test_user->user_id };
         $levels->{events}{"m.room.topic"} = 0;
      })->then( sub {
         $do_request_json_for->( $test_user,
            method => "PUT",
            uri    => "/rooms/$room_id/state/m.room.topic",

            content => { topic => "Here I can set the topic at powerlevel 0" },
         );
      });
   };
