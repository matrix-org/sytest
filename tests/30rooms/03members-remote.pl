use List::Util qw( first );
use List::UtilsBy qw( partition_by );

my $creator_fixture = local_user_fixture(
   # Some of these tests depend on the user having a displayname
   displayname => "My name here",
   avatar_url  => "mxc://foo/bar",
   with_events => 1,
);

my $remote_user_fixture = remote_user_fixture(
   displayname => "My remote name here",
   avatar_url  => "mxc://foo/remote",
   with_events => 1,
);

my $room_fixture = fixture(
   requires => [ $creator_fixture, room_alias_name_fixture() ],

   setup => sub {
      my ( $user, $room_alias_name ) = @_;

      matrix_create_room( $user,
         room_alias_name => $room_alias_name,
      );
   },
);

test "Remote users can join room by alias",
   requires => [ $remote_user_fixture, $room_fixture,
                 qw( can_join_room_by_alias can_get_room_membership )],

   proves => [qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      flush_events_for( $user )->then( sub {
         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/join/$room_alias",

            content => {},
         );
      });
   },

   check => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      matrix_get_room_state( $user, $room_id,
         type      => "m.room.member",
         state_key => $user->user_id,
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "join" or
            die "Expected membership to be 'join'";

         assert_json_keys( $body, qw( displayname avatar_url ) );

         Future->done(1);
      });
   };

test "New room members see their own join event",
   requires => [ $remote_user_fixture, $room_fixture,
                 qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      await_sync_timeline_contains( $user, $room_id, check => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";

         assert_json_keys( $event, qw( type sender ));
         return unless $event->{sender} eq $user->user_id;

         assert_json_keys( my $content = $event->{content}, qw( membership displayname avatar_url ));

         $content->{membership} eq "join" or
            die "Expected user membership as 'join'";

         return 1;
      });
   };

test "New room members see existing members' presence in room initialSync",
   deprecated_endpoints => 1,
   requires => [ $creator_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_join_remote_room_by_alias can_room_initial_sync )],

   do => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      ( repeat_until_true {
         matrix_initialsync_room( $user, $room_id )->then( sub {
            my ( $body ) = @_;

            log_if_fail "initialSync result", $body;

            my %presence = map { $_->{content}{user_id} => $_ } @{ $body->{presence} };

            # it's possible that the user's presence hasn't yet arrived at our
            # server (or hasn't propagated between the workers). In this case,
            # we expect the presence value to be either missing, or present
            # (hah!) with a default value.

            my $first_user_id = $first_user->user_id;
            my $first_presence = $presence{$first_user_id};

            if( not $first_presence ) {
               log_if_fail "No presence for user $first_user_id: retrying";
               return Future->done( undef );  # try again
            }

            assert_json_keys( $first_presence, qw( type content ));
            assert_json_keys( $first_presence->{content}, qw( presence ));

            if( $first_presence->{content}{presence} eq 'offline' &&
                   not exists $first_presence->{content}{last_active_ago} ) {
               log_if_fail "Default presence block for user $first_user_id: retrying";
               return Future->done( undef );  # try again
            }

            # otherwise, there should be a last_active_ago field.
            # (the user may or may not actually be online, because it might
            # have taken quite a while for us to spin up the prerequisites for
            # this test).
            assert_json_keys( $first_presence->{content}, qw( last_active_ago ));

            return Future->done( 1 );
         })
      });
   };

test "Existing members see new members' join events",
   requires => [ $creator_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      await_sync_timeline_contains( $first_user, $room_id, check => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";
         assert_json_keys( $event, qw( type sender ));
         return unless $event->{sender} eq $user->user_id;

         assert_json_keys( my $content = $event->{content}, qw( membership displayname avatar_url ));

         $content->{membership} eq "join" or
            die "Expected user membership as 'join'";

         return 1;
      });
   };

test "Existing members see new member's presence",
   requires => [ $creator_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      await_event_for( $first_user, filter => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.presence";
         assert_json_keys( $event, qw( type content ));
         assert_json_keys( my $content = $event->{content}, qw( user_id presence ));
         return unless $content->{user_id} eq $user->user_id;

         return 1;
      });
   };

test "New room members see first user's profile information in global initialSync",
   deprecated_endpoints => 1,
   requires => [ $creator_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_join_remote_room_by_alias can_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      matrix_initialsync( $user )->then( sub {
         my ( $body ) = @_;

         log_if_fail "initialSync result", $body;

         my $room = first { $_->{room_id} eq $room_id } @{$body->{rooms}};

         assert_json_keys( $room, qw( state ));
         assert_json_list( $room->{state} );

         my $first_user_id = $first_user->user_id;
         my $first_member = first {
            $_->{type} eq "m.room.member" and $_->{state_key} eq $first_user_id
         } @{ $room->{state} }
            or die "Failed to find first user $first_user_id in m.room.member state";

         assert_json_keys( $first_member, qw( user_id content ));
         assert_json_keys( my $content = $first_member->{content},
            qw( displayname avatar_url ));

         length $content->{displayname} or
            die "First user does not have profile displayname\n";
         length $content->{avatar_url} or
            die "First user does not have profile avatar_url\n";

         Future->done(1);
      });
   };

test "New room members see first user's profile information in per-room initialSync",
   deprecated_endpoints => 1,
   requires => [ $creator_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_room_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      matrix_initialsync_room( $user, $room_id )->then( sub {
         my ( $body ) = @_;

         log_if_fail "initialSync result", $body;

         assert_json_keys( $body, qw( state ));
         assert_json_list( $body->{state} );

         my $first_user_id = $first_user->user_id;
         my $first_member = first {
            $_->{type} eq "m.room.member" and $_->{state_key} eq $first_user_id
         } @{ $body->{state} }
            or die "Failed to find first user $first_user_id in m.room.member state";

         assert_json_keys( $first_member, qw( user_id content ));
         assert_json_keys( my $content = $first_member->{content},
            qw( displayname avatar_url ));

         length $content->{displayname} or
            die "First user does not have profile displayname\n";
         length $content->{avatar_url} or
            die "First user does not have profile avatar_url\n";

         Future->done(1);
      });
   };

test "Remote users may not join unfederated rooms",
   requires => [ local_user_fixture(), remote_user_fixture(), room_alias_name_fixture(),
                 qw( can_create_room_with_creation_content )],

   check => sub {
      my ( $creator, $remote_user, $room_alias_name ) = @_;

      matrix_create_room( $creator,
         room_alias_name  => $room_alias_name,
         creation_content => {
            "m.federate" => JSON::false,
         },
      )->then( sub {
         my ( undef, $room_alias ) = @_;

         matrix_join_room( $remote_user, $room_alias )
            ->main::expect_http_403;
      });
   };
