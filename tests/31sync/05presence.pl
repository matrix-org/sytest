use List::Util qw( first );

test "User sees their own presence in a sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my $filter_id;

      my $filter = {
         presence     => { types => [ "m.presence" ] },
         account_data => { types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_do_and_wait_for_sync( $user,
            do => sub { matrix_sync( $user, filter => $filter_id ) },
            check => sub { $_[0]->{presence}{events}[0] },
         );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $events = $body->{presence}{events};
         my $presence = first { $_->{type} eq "m.presence" } @$events
            or die "Expected to see our own presence";

         $presence->{sender} eq $user->user_id or die "Unexpected sender";
         $presence->{content}{presence} eq "online"
            or die "Expected to be online";

         Future->done(1);
      })
   };


test "User is offline if they set_presence=offline in their sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my $filter_id;

      my $filter = { presence => { types => [ "m.presence" ] } };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_sync( $user, filter => $filter_id, set_presence => "offline" );
      })->then( sub {
         my ( $body ) = @_;

         # Either I'm absent entirely, or I'm present in state "offline"; but
         # I shouldn't be "online"

         my $events = $body->{presence}{events};

         my $presence = first {
            $_->{type} eq "m.presence" and $_->{sender} eq $user->user_id
         } @$events;

         if( $presence ) {
            $presence->{content}{presence} eq "offline"
               or die "Expected to be offline";
         }

         # Additionally my presence should still be "offline"
         # But we can't assert on that yet - see SYT-34
         #
         # matrix_get_presence_status( $user );
         #    ->then( sub {
         #    my ( $status ) = @_;
         #    assert_eq( $status->{presence}, "offline" );
         # });

         Future->done(1);
      })
   };


test "User sees updates to presence from other users in the incremental sync.",
   requires => [ local_user_fixtures( 2, with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user_a, $user_b ) = @_;

      my ( $filter_id_a, $filter_id_b );

      my $filter = { presence => { types => [ "m.presence" ] } };

      Future->needs_all(
         matrix_create_filter( $user_a, $filter ),
         matrix_create_filter( $user_b, $filter ),
      )->then( sub {
         ( $filter_id_a, $filter_id_b ) = @_;

         # We can't use matrix_create_and_join since that polls the event
         # stream to check that the user has joined.
         matrix_create_room( $user_a )->then( sub {
            my ( $room_id ) = @_;

            matrix_join_room( $user_b, $room_id );
         });
      })->then( sub {
         matrix_sync( $user_a, filter => $filter_id_a );
      })->then( sub {
         # We sync again so that we get our own presence down.
         matrix_sync_again( $user_a, filter => $filter_id_a );
      })->then( sub {
         # Set user B's presence to online by syncing.
         matrix_sync( $user_b, filter => $filter_id_b );
      })->then( sub {
         matrix_sync_again( $user_a, filter => $filter_id_a, timeout => 1000 );
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "sync body", $body;

         my $events = $body->{presence}{events};
         my $presence = first { $_->{type} eq "m.presence" } @$events
            or die "Expected to see B's presence";

         $presence->{sender} eq $user_b->user_id or die "Unexpected sender";
         $presence->{content}{presence} eq "online"
            or die "Expected B to be online";

         Future->done(1);
      })
   };
