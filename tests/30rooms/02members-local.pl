use List::Util qw( first );

my $room_id;

prepare "Creating test room",
   requires => [qw( user more_users )],

   do => sub {
      my ( $user, $more_users ) = @_;

      # Don't use matrix_create_and_join_room here because we explicitly do
      # not want to wait for the join events; as we'll be testing later on
      # that we do in fact receive them

      Future->needs_all(
         map { flush_events_for( $_ ) } $user, @$more_users
      )->then( sub {
         matrix_create_room( $user )
      })->then( sub {
         ( $room_id ) = @_;

         Future->needs_all(
            map { matrix_join_room( $_, $room_id ) } @$more_users
         )
      });
   };

test "New room members see their own join event",
   requires => [qw( more_users )],

   do => sub {
      my ( $more_users ) = @_;

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
      } @$more_users );
   };

test "New room members see existing users' presence in room initialSync",
   requires => [qw( user more_users
                    can_room_initial_sync )],

   check => sub {
      my ( $first_user, $more_users ) = @_;

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

            require_json_keys( $presence{ $first_user->user_id }, qw( type content ));
            require_json_keys( $presence{ $first_user->user_id }{content},
               qw( presence status_msg last_active_ago ));

            Future->done(1);
         });
      } @$more_users );
   };

test "Existing members see new members' join events",
   requires => [qw( user more_users )],

   do => sub {
      my ( $user, $more_users ) = @_;

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
      } @$more_users );
   };

test "Existing members see new members' presence",
   requires => [qw( user more_users )],

   do => sub {
      my ( $user, $more_users ) = @_;

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
      } @$more_users );
   };

test "All room members see all room members' presence in global initialSync",
   requires => [qw( user more_users
                    can_initial_sync )],

   check => sub {
      my ( $user, $more_users ) = @_;
      my @all_users = ( $user, @$more_users );

      Future->needs_all( map {
         my $user = $_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/initialSync",
         )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( presence ));
            require_json_list( my $presence = $body->{presence} );

            my %presence_by_userid = map { $_->{content}{user_id} => $_ } @$presence;

            foreach my $user ( @all_users ) {
               my $user_id = $user->user_id;

               $presence_by_userid{$user_id} or
                  die "Expected to see presence of $user_id";

               require_json_keys( my $event = $presence_by_userid{$user_id},
                  qw( type content ) );
               require_json_keys( my $content = $event->{content},
                  qw( user_id presence last_active_ago ));

               $content->{presence} eq "online" or
                  die "Expected presence of $user_id to be online";
            }

            Future->done(1);
         });
      } @all_users );
   };

test "New room members see first user's profile information in global initialSync",
   requires => [qw( user more_users
                    can_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $more_users ) = @_;

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
      } @$more_users );
   };

test "New room members see first user's profile information in per-room initialSync",
   requires => [qw( user more_users
                    can_room_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $more_users ) = @_;

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
      } @$more_users );
   };
