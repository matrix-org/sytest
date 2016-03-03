use Future::Utils qw( repeat );

multi_test "New federated private chats get full presence information (SYN-115)",
   requires => [ local_user_fixture(), remote_user_fixture(),
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
         matrix_create_room( $alice,
            visibility => "private",
         )->SyTest::pass_on_done( "Created a room" )
      })->then( sub {
         ( $room_id ) = @_;

         # Alice invites Bob
         matrix_invite_user_to_room( $alice, $bob, $room_id )
            ->SyTest::pass_on_done( "Sent invite" )
      })->then( sub {

         # Bob should receive the invite
         await_event_for( $bob, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member" and
                          $event->{room_id} eq $room_id and
                          $event->{state_key} eq $bob->user_id and
                          $event->{content}{membership} eq "invite";

            return 1;
         })->SyTest::pass_on_done( "Received invite" )
      })->then( sub {

         # Bob accepts the invite by joining the room
         matrix_join_room( $bob, $room_id )
            ->SyTest::pass_on_done( "Joined room" )
      })->then( sub {

         # At this point, both users should see both users' presence, either
         # right now via global /initialSync, or should soon receive an
         # m.presence event from /events.
         Future->needs_all( map {
            my $user = $_;

            my %presence_by_userid;

            my $f = repeat {
               my $is_initial = !$_[0];

               do_request_json_for( $user,
                  method => "GET",
                  uri    => $is_initial ? "/r0/initialSync" : "/r0/events",
                  params => { from => $user->eventstream_token, timeout => 500 }
               )->then( sub {
                  my ( $body ) = @_;
                  $user->eventstream_token = $body->{end};

                  my @presence = $is_initial
                     ? @{ $body->{presence} }
                     : grep { $_->{type} eq "m.presence" } @{ $body->{chunk} };

                  foreach my $event ( @presence ) {
                     my $user_id = $event->{content}{user_id};
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
