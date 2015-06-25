multi_test "New federated private chats get full presence information (SYN-115)",
   requires => [qw( register_new_user http_clients do_request_json_for flush_events_for await_event_for
                    can_register can_create_private_room )],

   do => sub {
      my ( $register_new_user, $clients, $do_request_json_for, $flush_events_for, $await_event_for ) = @_;
      my ( $http1, $http2 ) = @$clients;

      my ( $alice, $bob );
      my $room;

      # Register two users
      Future->needs_all(
         $register_new_user->( $http1, "90jira-SYN-115_alice" ),
         $register_new_user->( $http2, "90jira-SYN-115_bob" ),
      )->then( sub {
         ( $alice, $bob ) = @_;

         pass "Registered users";

         # Flush event streams for both; as a side-effect will mark presence 'online'
         Future->needs_all(
            $flush_events_for->( $alice ),
            $flush_events_for->( $bob   ),
         )
      })->then( sub {
         # Have Alice create a new private room
         $do_request_json_for->( $alice,
            method => "POST",
            uri    => "/createRoom",
            content => { visibility => "private" },
         )
      })->then( sub {
         ( $room ) = @_;

         pass "Created a room";

         # Alice invites Bob
         $do_request_json_for->( $alice,
            method => "POST",
            uri    => "/rooms/$room->{room_id}/invite",

            content => { user_id => $bob->user_id },
         );
      })->then( sub {
         pass "Sent invite";

         # Bob should receive the invite
         $await_event_for->( $bob, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member" and
                          $event->{room_id} eq $room->{room_id} and
                          $event->{state_key} eq $bob->user_id and
                          $event->{content}{membership} eq "invite";

            return 1;
         });
      })->then( sub {
         pass "Received invite";

         # Bob accepts the invite by joining the room
         $do_request_json_for->( $bob,
            method => "POST",
            uri    => "/rooms/$room->{room_id}/join",

            content => {},
         );
      })->then( sub {
         pass "Joined room";

         # At this point, both users should see both users' presence, either
         # right now via global /initialSync, or should soon receive an
         # m.presence event from /events.
         Future->needs_all( map {
            my $user = $_;

            my %presence_by_userid;

            my $f = repeat {
               my $is_initial = !$_[0];

               $do_request_json_for->( $user,
                  method => "GET",
                  uri    => $is_initial ? "/initialSync" : "/events",
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
         } $alice, $bob );
      })->then( sub {
         pass "Both users see both users' presence";

         Future->done(1);
      });
   };
