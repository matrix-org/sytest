use List::Util qw( first );
use List::UtilsBy qw( partition_by );

my $creator_fixture = local_user_fixture(
   # Some of these tests depend on the user having a displayname
   displayname => "My name here",
   avatar_url => "mxc://foo/bar",
);

my $remote_user_fixture = remote_user_fixture(
   displayname => "My remote name here",
   avatar_url => "mxc://foo/remote",
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

      await_event_for( $user, filter => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";

         assert_json_keys( $event, qw( type room_id user_id ));
         return unless $event->{room_id} eq $room_id;
         return unless $event->{user_id} eq $user->user_id;

         assert_json_keys( my $content = $event->{content}, qw( membership displayname avatar_url ));

         $content->{membership} eq "join" or
            die "Expected user membership as 'join'";

         return 1;
      });
   };

test "New room members see existing members' presence in room initialSync",
   requires => [ $creator_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_join_remote_room_by_alias can_room_initial_sync )],

   do => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      ( repeat_until_true {
         matrix_initialsync_room( $user, $room_id )->then( sub {
            my ( $body ) = @_;

            my %presence = map { $_->{content}{user_id} => $_ } @{ $body->{presence} };

            $presence{$first_user->user_id} or
               return Future->done( undef );  # try again

            return Future->done( \%presence );
         })
      })->then( sub {
         my ( $presencemap ) = @_;

         assert_json_keys( $presencemap->{ $first_user->user_id },
            qw( type content ));
         assert_json_keys( $presencemap->{ $first_user->user_id }{content},
            qw( presence last_active_ago ));

         Future->done(1);
      });
   };

test "Existing members see new members' join events",
   requires => [ $creator_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      await_event_for( $first_user, filter => sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";
         assert_json_keys( $event, qw( type room_id user_id ));
         return unless $event->{room_id} eq $room_id;
         return unless $event->{user_id} eq $user->user_id;

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
   requires => [ $creator_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_join_remote_room_by_alias can_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      matrix_initialsync( $user )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( presence ));
         assert_json_list( $body->{presence} );

         my %presence_by_userid = map { $_->{content}{user_id} => $_ } @{ $body->{presence} };

         my $presence = $presence_by_userid{ $first_user->user_id } or
            die "Failed to find presence of first user";

         assert_json_keys( $presence, qw( content ));
         assert_json_keys( my $content = $presence->{content},
            qw( user_id presence ));

         Future->done(1);
      });
   };

test "New room members see first user's profile information in per-room initialSync",
   requires => [ $creator_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_room_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      matrix_initialsync_room( $user, $room_id )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( state ));
         assert_json_list( $body->{state} );

         my $first_member = first {
            $_->{type} eq "m.room.member" and $_->{state_key} eq $first_user->user_id
         } @{ $body->{state} }
            or die "Failed to find first user in m.room.member state";

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
