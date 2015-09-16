use Future::Utils 0.18 qw( try_repeat );

test "Remote users can join room by alias",
   requires => [qw( do_request_json_for flush_events_for remote_users room_alias room_id
                    can_join_room_by_alias can_get_room_membership )],

   provides => [qw( can_join_remote_room_by_alias )],

   do => sub {
      my ( $do_request_json_for, $flush_events_for, $remote_users, $room_alias ) = @_;
      my $user = $remote_users->[0];

      $flush_events_for->( $user )->then( sub {
         $do_request_json_for->( $user,
            method => "POST",
            uri    => "/api/v1/join/$room_alias",

            content => {},
         );
      });
   },

   check => sub {
      my ( $do_request_json_for, undef, $remote_users, undef, $room_id ) = @_;
      my $user = $remote_users->[0];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.member/:user_id",
      )->then( sub {
         my ( $body ) = @_;

         $body->{membership} eq "join" or
            die "Expected membership to be 'join'";

         provide can_join_remote_room_by_alias => 1;

         Future->done(1);
      });
   };

prepare "More remote room members",
   requires => [qw( do_request_json_for flush_events_for remote_users room_alias
                    can_join_remote_room_by_alias )],

   do => sub {
      my ( $do_request_json_for, $flush_events_for, $remote_users, $room_alias ) = @_;
      my ( undef, @users ) = @$remote_users;

      Future->needs_all( map {
         my $user = $_;

         $flush_events_for->( $user )->then( sub {
            $do_request_json_for->( $user,
               method => "POST",
               uri    => "/api/v1/join/$room_alias",

               content => {},
            );
         });
      } @users );
   };

test "New room members see their own join event",
   requires => [qw( await_event_for remote_users room_id
                    can_join_remote_room_by_alias )],

   await => sub {
      my ( $await_event_for, $remote_users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $await_event_for->( $user, sub {
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
   requires => [qw( do_request_json_for user remote_users room_id
                    can_join_remote_room_by_alias can_room_initial_sync )],

   await => sub {
      my ( $do_request_json_for, $first_user, $remote_users, $room_id ) = @_;

      try_repeat {
         Future->needs_all( map {
            my $user = $_;

            $do_request_json_for->( $user,
               method => "GET",
               uri    => "/api/v1/rooms/$room_id/initialSync",
            )->then( sub {
               my ( $body ) = @_;

               my %presence;
               $presence{ $_->{content}{user_id} } = $_ for @{ $body->{presence} };

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
   requires => [qw( await_event_for user remote_users room_id
                    can_join_remote_room_by_alias )],

   await => sub {
      my ( $await_event_for, $user, $remote_users, $room_id ) = @_;

      Future->needs_all( map {
         my $other_user = $_;

         $await_event_for->( $user, sub {
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
   requires => [qw( await_event_for user remote_users
                    can_join_remote_room_by_alias )],

   await => sub {
      my ( $await_event_for, $user, $remote_users ) = @_;

      Future->needs_all( map {
         my $other_user = $_;

         $await_event_for->( $user, sub {
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
   requires => [qw( do_request_json_for user remote_users
                    can_create_room can_join_remote_room_by_alias can_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $do_request_json_for, $first_user, $remote_users ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $do_request_json_for->( $user,
            method => "GET",
            uri    => "/api/v1/initialSync",
         )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( presence ));
            require_json_list( $body->{presence} );

            my %presence_by_userid;
            $presence_by_userid{ $_->{content}{user_id} } = $_ for @{ $body->{presence} };

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
   requires => [qw( do_request_json_for user remote_users room_id
                    can_create_room can_join_room_by_id can_room_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $do_request_json_for, $first_user, $remote_users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $do_request_json_for->( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/initialSync",
         )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( state ));
            require_json_list( $body->{state} );

            my %state_by_type_key;
            $state_by_type_key{ $_->{type} }{ $_->{state_key} } = $_ for
               @{ $body->{state} };

            my $first_member = $state_by_type_key{"m.room.member"}{ $first_user->user_id }
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
