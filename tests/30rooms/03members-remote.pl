use Future::Utils 0.18 qw( try_repeat );
use List::Util qw( first );
use List::UtilsBy qw( partition_by );

my $room_id;
my $room_alias;

prepare "Creating test room",
   requires => [qw( user )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user,
         room_alias_name => "03members-remote",
      )->on_done( sub {
         ( $room_id, $room_alias ) = @_;
      });
   };

test "Remote users can join room by alias",
   requires => [qw( remote_users
                    can_join_room_by_alias can_get_room_membership )],

   provides => [qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $remote_users ) = @_;
      my $user = $remote_users->[0];

      flush_events_for( $user )->then( sub {
         do_request_json_for( $user,
            method => "POST",
            uri    => "/api/v1/join/$room_alias",

            content => {},
         );
      });
   },

   check => sub {
      my ( $remote_users ) = @_;
      my $user = $remote_users->[0];

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

prepare "More remote room members",
   requires => [qw( remote_users
                    can_join_remote_room_by_alias )],

   do => sub {
      my ( $remote_users ) = @_;
      my ( undef, @users ) = @$remote_users;

      Future->needs_all( map {
         my $user = $_;

         flush_events_for( $user )->then( sub {
            do_request_json_for( $user,
               method => "POST",
               uri    => "/api/v1/join/$room_alias",

               content => {},
            );
         });
      } @users );
   };

test "New room members see their own join event",
   requires => [qw( remote_users
                    can_join_remote_room_by_alias )],

   do => sub {
      my ( $remote_users ) = @_;

      Future->needs_all( map {
         my $user = $_;

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
      } @$remote_users );
   };

test "New room members see existing members' presence in room initialSync",
   requires => [qw( user remote_users
                    can_join_remote_room_by_alias can_room_initial_sync )],

   do => sub {
      my ( $first_user, $remote_users ) = @_;

      try_repeat {
         Future->needs_all( map {
            my $user = $_;

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
                  qw( presence status_msg last_active_ago ));

               Future->done(1);
            });
         } @$remote_users )
            ->else_with_f( sub {
               my ( $f ) = @_; delay( 0.2 )->then( sub { $f } );
            });
      } until => sub { !$_[0]->failure };
   };

test "Existing members see new members' join events",
   requires => [qw( user remote_users
                    can_join_remote_room_by_alias )],

   do => sub {
      my ( $user, $remote_users ) = @_;

      Future->needs_all( map {
         my $other_user = $_;

         await_event_for( $user, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.member";
            require_json_keys( $event, qw( type room_id user_id ));
            return unless $event->{room_id} eq $room_id;
            return unless $event->{user_id} eq $other_user->user_id;

            require_json_keys( my $content = $event->{content}, qw( membership ));

            $content->{membership} eq "join" or
               die "Expected user membership as 'join'";

            return 1;
         });
      } @$remote_users );
   };

test "Existing members see new member's presence",
   requires => [qw( user remote_users
                    can_join_remote_room_by_alias )],

   do => sub {
      my ( $user, $remote_users ) = @_;

      Future->needs_all( map {
         my $other_user = $_;

         await_event_for( $user, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";
            require_json_keys( $event, qw( type content ));
            require_json_keys( my $content = $event->{content}, qw( user_id presence ));
            return unless $content->{user_id} eq $other_user->user_id;

            return 1;
         });
      } @$remote_users );
   };

test "New room members see first user's profile information in global initialSync",
   requires => [qw( user remote_users
                    can_join_remote_room_by_alias can_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $remote_users ) = @_;

      Future->needs_all( map {
         my $user = $_;

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
      } @$remote_users );
   };

test "New room members see first user's profile information in per-room initialSync",
   requires => [qw( user remote_users
                    can_room_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $remote_users ) = @_;

      Future->needs_all( map {
         my $user = $_;

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
      } @$remote_users );
   };
