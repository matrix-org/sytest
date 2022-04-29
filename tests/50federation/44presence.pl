use Future::Utils qw( repeat );

multi_test "New federated private chats get full presence information (SYN-115)",
   requires => [ local_user_fixture(), remote_user_fixture( with_events => 1 ),
                 qw( can_create_private_room )],

   do => sub {
      my ( $alice, $bob ) = @_;

      my $room_id;

      # Flush event streams for both; as a side-effect will mark presence 'online'
      Future->needs_all(
         flush_events_for( $alice ),
         flush_events_for( $bob   ),
      )->then( sub {

         # Have Alice create a new private room
         matrix_create_room_synced( $alice,
            visibility => "private",
         )->SyTest::pass_on_done( "Created a room" )
      })->then( sub {
         ( $room_id ) = @_;

         # Alice invites Bob
         matrix_invite_user_to_room( $alice, $bob, $room_id )
            ->SyTest::pass_on_done( "Sent invite" )
      })->then( sub {

         # Bob should receive the invite
         await_sync( $bob, check => sub {
            my ( $body ) = @_;

            return 0 unless exists $body->{rooms}{invite}{$room_id};
            return $body->{rooms}{invite}{$room_id};
         })->SyTest::pass_on_done( "Bob received invite" ),
      })->then( sub {

         # Bob accepts the invite by joining the room
         matrix_join_room_synced( $bob, $room_id )
            ->SyTest::pass_on_done( "Joined room" )
      })->then( sub {

         # At this point, both users should see both users' presence, either
         # right now via global /initialSync, or should soon receive an
         # m.presence event from /events.
         Future->needs_all( map {
            my $user = $_;

            my %presence_by_userid;

            my $f = repeat {

               await_sync_presence_contains( $user, check => sub {
                  my ( $event ) = @_;
                  return unless $event->{type} eq "m.presence";
                  return 1;
               })->then( sub {
                  my ( $body ) = @_;
                  my @presence = @{ $body->{presence}{events} };

                  foreach my $event ( @presence ) {
                     
                     my $user_id = $event->{sender};
                     pass "User ${\$user->user_id} received presence for $user_id";
                     $presence_by_userid{$user_id} = $event;
                  }

                  Future->done(1);
               });
            } until => sub { keys %presence_by_userid == 2 };

            Future->wait_any(
               $f,

               delay( 2 )
                  ->then_fail( "Timed out waiting for ${\$user->user_id} to receive all presence" )
            );
         } $alice, $bob )
         ->SyTest::pass_on_done( "Both users see both users' presence" )
      })->then_done(1);
   };
