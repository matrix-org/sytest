use Future::Utils 0.18 qw( try_repeat );
use List::Util qw( first );
use List::UtilsBy qw( partition_by );

my $creator_preparer = local_user_preparer(
   # Some of these tests depend on the user having a displayname
   displayname => "My name here",
);

my $remote_user_preparer = remote_user_preparer();

my $room_preparer = preparer(
   requires => [ $creator_preparer ],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user,
         room_alias_name => "03members-remote"
      );
   },
);

test "Remote users can join room by alias",
   requires => [ $remote_user_preparer, $room_preparer,
                 qw( can_join_room_by_alias can_get_room_membership )],

   provides => [qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      flush_events_for( $user )->then( sub {
         do_request_json_for( $user,
            method => "POST",
            uri    => "/api/v1/join/$room_alias",

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

         provide can_join_remote_room_by_alias => 1;

         Future->done(1);
      });
   };

test "New room members see their own join event",
   requires => [ $remote_user_preparer, $room_preparer,
                 qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      await_event_for( $user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";

         require_json_keys( $event, qw( type room_id user_id ));
         return unless $event->{room_id} eq $room_id;
         return unless $event->{user_id} eq $user->user_id;

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "join" or
            die "Expected user membership as 'join'";

         return 1;
      });
   };

test "New room members see existing members' presence in room initialSync",
   requires => [ $creator_preparer, $remote_user_preparer, $room_preparer,
                 qw( can_join_remote_room_by_alias can_room_initial_sync )],

   do => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      try_repeat {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/initialSync",
         )->then( sub {
            my ( $body ) = @_;

            my %presence = map { $_->{content}{user_id} => $_ } @{ $body->{presence} };

            $presence{$first_user->user_id} or
               die "Expected to find initial user's presence";

            require_json_keys( $presence{ $first_user->user_id },
               qw( type content ));
            require_json_keys( $presence{ $first_user->user_id }{content},
               qw( presence last_active_ago ));

            Future->done(1);
         })->else_with_f( sub {
            my ( $f ) = @_; delay( 0.2 )->then( sub { $f } );
         });
      } until => sub { !$_[0]->failure };
   };

test "Existing members see new members' join events",
   requires => [ $creator_preparer, $remote_user_preparer, $room_preparer,
                 qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      await_event_for( $first_user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";
         require_json_keys( $event, qw( type room_id user_id ));
         return unless $event->{room_id} eq $room_id;
         return unless $event->{user_id} eq $user->user_id;

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "join" or
            die "Expected user membership as 'join'";

         return 1;
      });
   };

test "Existing members see new member's presence",
   requires => [ $creator_preparer, $remote_user_preparer, $room_preparer,
                 qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      await_event_for( $first_user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.presence";
         require_json_keys( $event, qw( type content ));
         require_json_keys( my $content = $event->{content}, qw( user_id presence ));
         return unless $content->{user_id} eq $user->user_id;

         return 1;
      });
   };

test "New room members see first user's profile information in global initialSync",
   requires => [ $creator_preparer, $remote_user_preparer, $room_preparer,
                 qw( can_join_remote_room_by_alias can_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( presence ));
         require_json_list( $body->{presence} );

         my %presence_by_userid = map { $_->{content}{user_id} => $_ } @{ $body->{presence} };

         my $presence = $presence_by_userid{ $first_user->user_id } or
            die "Failed to find presence of first user";

         require_json_keys( $presence, qw( content ));
         require_json_keys( my $content = $presence->{content},
            qw( user_id displayname avatar_url ));

         Future->done(1);
      });
   };

test "New room members see first user's profile information in per-room initialSync",
   requires => [ $creator_preparer, $remote_user_preparer, $room_preparer,
                 qw( can_room_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $user, $room_id, $room_alias ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( state ));
         require_json_list( $body->{state} );

         my $first_member = first {
            $_->{type} eq "m.room.member" and $_->{state_key} eq $first_user->user_id
         } @{ $body->{state} }
            or die "Failed to find first user in m.room.member state";

         require_json_keys( $first_member, qw( user_id content ));
         require_json_keys( my $content = $first_member->{content},
            qw( displayname avatar_url ));

         length $content->{displayname} or
            die "First user does not have profile displayname\n";
         length $content->{avatar_url} or
            die "First user does not have profile avatar_url\n";

         Future->done(1);
      });
   };
