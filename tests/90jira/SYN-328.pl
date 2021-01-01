multi_test "Typing notifications don't leak",
   requires => [ local_user_fixtures( 3, with_events => 1 ),
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
            uri    => "/r0/rooms/$room_id/typing/:user_id",

            content => { typing => JSON::true, timeout => 30000 * $TIMEOUT_FACTOR }, # msec
         );
      })->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_sync_ephemeral_contains($recvuser, $room_id,
               check => sub {
                  my ( $event ) = @_;
                  return unless $event->{type} eq "m.typing";
                  return 1;
               },
            )
         } $creator, $member )
            ->SyTest::pass_on_done( "Members received notification" )
      })->then( sub {

         # Wait on a different user to see if we get a typing notification
         Future->wait_any(
            delay( 2 ),

            await_sync_ephemeral_contains($nonmember, $room_id,
               check => sub {
                  my ( $event ) = @_;
                  return unless $event->{type} eq "m.typing";
                  return 1;
               },
            )->then_fail( "Received unexpected typing notification" ),
         )->SyTest::pass_on_done( "Non-member did not receive it up to timeout" )
      })->then_done(1);
   };
