use List::Util qw( first );

my $creator_preparer = local_user_preparer(
   # Some of these tests depend on the user having a displayname
   displayname => "My name here",
);

my $local_user_preparer = local_user_preparer();

my $room_preparer = preparer(
   requires => [ $creator_preparer, $local_user_preparer ],

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
   requires => [ $local_user_preparer, $room_preparer ],

   do => sub {
      my ( $local_user, $room_id ) = @_;

      await_event_for( $local_user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";

         require_json_keys( $event, qw( type room_id user_id ));
         return unless $event->{room_id} eq $room_id;
         return unless $event->{user_id} eq $local_user->user_id;

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "join" or
            die "Expected user membership as 'join'";

         return 1;
      });
   };

test "New room members see existing users' presence in room initialSync",
   requires => [ $creator_preparer, $local_user_preparer, $room_preparer,
                 qw( can_room_initial_sync )],

   check => sub {
      my ( $first_user, $local_user, $room_id ) = @_;

      do_request_json_for( $local_user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         my %presence = map { $_->{content}{user_id} => $_ } @{ $body->{presence} };

         $presence{$first_user->user_id} or
            die "Expected to find initial user's presence";

         require_json_keys( $presence{ $first_user->user_id }, qw( type content ));
         require_json_keys( $presence{ $first_user->user_id }{content},
            qw( presence last_active_ago ));

         # No status_msg or last_active_ago - see SYT-34

         Future->done(1);
      });
   };

test "Existing members see new members' join events",
   requires => [ $creator_preparer, $local_user_preparer, $room_preparer ],

   do => sub {
      my ( $first_user, $local_user, $room_id ) = @_;

      await_event_for( $first_user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.room.member";
         require_json_keys( $event, qw( type room_id user_id ));
         return unless $event->{room_id} eq $room_id;
         return unless $event->{user_id} eq $local_user->user_id;

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "join" or
            die "Expected user membership as 'join'";

         return 1;
      });
   };

test "Existing members see new members' presence",
   requires => [ $creator_preparer, $local_user_preparer, $room_preparer ],

   do => sub {
      my ( $first_user, $local_user ) = @_;

      await_event_for( $first_user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.presence";
         require_json_keys( $event, qw( type content ));
         require_json_keys( my $content = $event->{content}, qw( user_id presence ));
         return unless $content->{user_id} eq $local_user->user_id;

         return 1;
      });
   };

test "All room members see all room members' presence in global initialSync",
   requires => [ $creator_preparer, $local_user_preparer, $room_preparer,
                 qw( can_initial_sync )],

   check => sub {
      my ( $first_user, $local_user, $room_id ) = @_;
      my @all_users = ( $first_user, $local_user );

      Future->needs_all( map {
         my $user = $_;

         matrix_initialsync( $user )->then( sub {
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
   requires => [ $creator_preparer, $local_user_preparer, $room_preparer,
                 qw( can_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $local_user, $room_id ) = @_;

      matrix_initialsync( $local_user )->then( sub {
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
   requires => [ $creator_preparer, $local_user_preparer, $room_preparer,
                 qw( can_room_initial_sync can_set_displayname can_set_avatar_url )],

   check => sub {
      my ( $first_user, $local_user, $room_id ) = @_;

      do_request_json_for( $local_user,
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
