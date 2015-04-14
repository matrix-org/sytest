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

my $set_user_powerlevel = sub {
   my ( $do_request_json_for, $opuser, $user_id, $level ) = @_;

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

sub test_powerlevel
{
   my ( $name, %args ) = @_;

   my $do = $args{do};

   multi_test $name,,
      requires => [qw( do_request_json_for user local_users ), @{ $args{requires} } ],

      do => sub {
         my ( $do_request_json_for, $user, $local_users ) = @_;
         my $test_user = $local_users->[1];

         # Fails at powerlevel 0
         $set_user_powerlevel->( $do_request_json_for, $user,
            $test_user->user_id, 0
         )->then( sub {
            $do->( $do_request_json_for, $test_user );
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
            $set_user_powerlevel->( $do_request_json_for, $user,
               $test_user->user_id, 100
            )
         })->then( sub {
            $do->( $do_request_json_for, $test_user );
         })->on_done( sub {
            pass( "Succeeds at powerlevel 100" );
         })
      };
}

test_powerlevel "'ban' event respects room powerlevel",
   requires => [qw( can_ban_room )],

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
##    requires => [qw( can_invite_room )],
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
   requires => [qw( can_set_room_name )],

   do => sub {
      my ( $do_request_json_for, $test_user ) = @_;

      $do_request_json_for->( $test_user,
         method => "PUT",
         uri    => "/rooms/$room_id/state/m.room.name",

         content => { name => "A new room name" },
      );
   };
