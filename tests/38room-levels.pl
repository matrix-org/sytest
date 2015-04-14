use List::Util qw( first );

my $room_id;

prepare "Creating a new test room",
   requires => [qw( do_request_json_for local_users
                    can_create_room can_join_room_by_id )],

   do => sub {
      my ( $do_request_json_for, $local_users ) = @_;
      my $creator   = $local_users->[0];
      my $test_user = $local_users->[1];

      $do_request_json_for->( $creator,
         method => "POST",
         uri    => "/createRoom",

         content => { visibility => "public" },
      )->then( sub {
         my ( $body ) = @_;

         $room_id = $body->{room_id};

         $do_request_json_for->( $test_user,
            method => "POST",
            uri    => "/rooms/$room_id/join",

            content => {},
         );
      });
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
            $do->( @dependencies );
         })->then(
            sub { # done
               Future->fail( "Expected to fail at powerlevel=0 but it didn't" );
            },
            sub { # fail
               my ( $message, $name, $response, $request ) = @_;
               $name eq "http" or
                  return Future->fail( @_ );
               $response and $response->code == 403 or
                  return Future->fail( @_ );

               Future->done;
            },
         )->then( sub {
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
