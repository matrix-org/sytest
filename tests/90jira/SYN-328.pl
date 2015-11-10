multi_test "Typing notifications don't leak",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_set_room_typing )],

   do => sub {
      my ( $creator, $member, $nonmember ) = @_;

      my $room_id;

      matrix_create_and_join_room( [ $creator, $member ] )
         ->SyTest::pass_on_done( "Created room" )
      ->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $creator,
            method => "PUT",
            uri    => "/api/v1/rooms/$room_id/typing/:user_id",

            content => { typing => 1, timeout => 30000 }, # msec
         );
      })->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_event_for( $recvuser, sub {
               my ( $event ) = @_;

               return $event->{type} eq "m.typing" &&
                      $event->{room_id} eq $room_id;
            })
         } $creator, $member )
            ->SyTest::pass_on_done( "Members received notification" )
      })->then( sub {

         Future->wait_any(
            delay( 2 ),

            await_event_for( $nonmember, sub {
               my ( $event ) = @_;

               return $event->{type} eq "m.typing" &&
                      $event->{room_id} eq $room_id;
            })->then_fail( "Received unexpected typing notification" ),
         )->SyTest::pass_on_done( "Non-member did not receive it up to timeout" )
      })->then_done(1);
   };
