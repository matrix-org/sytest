use List::Util qw( first );

my $creator_fixture = local_user_fixture(
   # Some of these tests depend on the user having a displayname
   displayname => "My name here",
   avatar_url => "mxc://foo/bar",
);

my $local_user_fixture = local_user_fixture();

my $room_fixture = fixture(
   requires => [ $creator_fixture, $local_user_fixture ],

   setup => sub {
      my ( $creator, $local_user ) = @_;

      # Don't use matrix_create_and_join_room here because we explicitly do
      # not want to wait for the join events; as we'll be testing later on
      # that we do in fact receive them

      Future->needs_all(
         map { flush_events_for( $_ ) } $creator, $local_user
      )->then( sub {
         matrix_create_room( $creator )
      })->then( sub {
         my ( $room_id ) = @_;

         matrix_join_room( $local_user, $room_id )
            ->then_done( $room_id );
      });
   },
);

test "New room members see their own join event",
   requires => [ $local_user_fixture, $room_fixture ],

   do => sub {
      my ( $local_user, $room_id ) = @_;

      await_sync_timeline_contains( $local_user, $room_id, check => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";

         assert_json_keys( $event, qw( type sender ));
         return unless $event->{sender} eq $local_user->user_id;

         assert_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "join" or
            die "Expected user membership as 'join'";

         return 1;
      });
   };

test "New room members see existing users' presence in room initialSync",
   requires => [ $creator_fixture, $local_user_fixture, $room_fixture,
                 qw( can_room_initial_sync deprecated_endpoints )],

   check => sub {
      my ( $first_user, $local_user, $room_id ) = @_;

      matrix_initialsync_room( $local_user, $room_id )
      ->then( sub {
         my ( $body ) = @_;

         my %presence = map { $_->{content}{user_id} => $_ } @{ $body->{presence} };

         $presence{$first_user->user_id} or
            die "Expected to find initial user's presence";

         assert_json_keys( $presence{ $first_user->user_id }, qw( type content ));
         assert_json_keys( $presence{ $first_user->user_id }{content},
            qw( presence ));

         # No status_msg or last_active_ago - see SYT-34

         Future->done(1);
      });
   };

test "Existing members see new members' join events",
   requires => [ $creator_fixture, $local_user_fixture, $room_fixture ],

   do => sub {
      my ( $first_user, $local_user, $room_id ) = @_;

      await_sync_timeline_contains( $first_user, $room_id, check => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";
         assert_json_keys( $event, qw( type sender ));
         return unless $event->{sender} eq $local_user->user_id;

         assert_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "join" or
            die "Expected user membership as 'join'";

         return 1;
      });
   };

test "Existing members see new members' presence",
   requires => [ $creator_fixture, $local_user_fixture, $room_fixture ],

   do => sub {
      my ( $first_user, $local_user ) = @_;

      await_event_for( $first_user, filter => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.presence";
         assert_json_keys( $event, qw( type content ));
         assert_json_keys( my $content = $event->{content}, qw( user_id presence ));
         return unless $content->{user_id} eq $local_user->user_id;

         return 1;
      });
   };

test "All room members see all room members' presence in global initialSync",
   requires => [ $creator_fixture, $local_user_fixture, $room_fixture,
                 qw( can_initial_sync deprecated_endpoints )],

   check => sub {
      my ( $first_user, $local_user, $room_id ) = @_;
      my @all_users = ( $first_user, $local_user );

      Future->needs_all( map {
         my $user = $_;

         matrix_initialsync( $user )->then( sub {
            my ( $body ) = @_;

            assert_json_keys( $body, qw( presence ));
            assert_json_list( my $presence = $body->{presence} );

            my %presence_by_userid = map { $_->{content}{user_id} => $_ } @$presence;

            foreach my $user ( @all_users ) {
               my $user_id = $user->user_id;

               $presence_by_userid{$user_id} or
                  die "Expected to see presence of $user_id";

               assert_json_keys( my $event = $presence_by_userid{$user_id},
                  qw( type content ) );
               assert_json_keys( my $content = $event->{content},
                  qw( user_id presence last_active_ago ));

               $content->{presence} eq "online" or
                  die "Expected presence of $user_id to be online";
            }

            Future->done(1);
         });
      } @all_users );
   };
