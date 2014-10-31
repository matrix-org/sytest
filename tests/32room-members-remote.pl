test "Remote users can join room by alias",
   requires => [qw( do_request_json_for flush_events_for remote_users room_alias room_id
                    can_join_room_by_alias can_get_room_membership )],

   do => sub {
      my ( $do_request_json_for, $flush_events_for, $remote_users, $room_alias ) = @_;
      my $user = $remote_users->[0];

      $flush_events_for->( $user )->then( sub {
         $do_request_json_for->( $user,
            method => "POST",
            uri    => "/join/$room_alias",

            content => {},
         );
      });
   },

   check => sub {
      my ( $do_request_json_for, undef, $remote_users, undef, $room_id ) = @_;
      my $user = $remote_users->[0];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/rooms/$room_id/state/m.room.member/:user_id",
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
               uri    => "/join/$room_alias",

               content => {},
            );
         });
      } @users );
   };

test "New room members see their own join event",
   requires => [qw( GET_new_events_for remote_users room_id
                    can_join_remote_room_by_alias )],

   check => sub {
      my ( $GET_new_events_for, $remote_users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $GET_new_events_for->( $user, "m.room.member",
            timeout => 50,
         )->then( sub {
            my $found;
            foreach my $event ( @_ ) {
               json_keys_ok( $event, qw( type room_id user_id membership ));
               next unless $event->{room_id} eq $room_id;
               next unless $event->{user_id} eq $user->user_id;

               $found++;

               $event->{membership} eq "join" or
                  die "Expected user membership as 'join'";
            }

            $found or
               die "Failed to find an appropriate m.room.member event";

            Future->done(1);
         });
      } @$remote_users );
   };

test "New room members also see original members' presence",
   requires => [qw( GET_new_events_for user remote_users
                    can_join_remote_room_by_alias )],

   check => sub {
      my ( $GET_new_events_for, $first_user, $remote_users ) = @_;

      Future->needs_all( map {
         my $user = $_;

         # GET_new instead of saved because they probably don't come in the
         # chunk over federation
         $GET_new_events_for->( $user, "m.presence",
            timeout => 50,
         )->then( sub {
            my $found;
            foreach my $event ( @_ ) {
               json_keys_ok( $event, qw( type content ));
               json_keys_ok( my $content = $event->{content}, qw( user_id presence ));

               next unless $content->{user_id} eq $first_user->user_id;

               $found++;
            }

            $found or
               die "Failed to find presence of existing room member";

            Future->done(1);
         });
      } @$remote_users );
   };

test "Existing members see new members' join events",
   requires => [qw( GET_new_events_for user remote_users room_id
                    can_join_remote_room_by_alias )],

   check => sub {
      my ( $GET_new_events_for, $user, $remote_users, $room_id ) = @_;

      $GET_new_events_for->( $user, "m.room.member" )->then( sub {
         my %found_user;
         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( type room_id user_id membership ));
            next unless $event->{room_id} eq $room_id;

            $found_user{$event->{user_id}}++;

            $event->{membership} eq "join" or
               die "Expected user membership as 'join'";
         }

         $found_user{$_->user_id} or die "Failed to find membership of ${\$_->user_id}"
            for @$remote_users;

         Future->done(1);
      });
   };

test "Existing members see new member's presence",
   requires => [qw( GET_new_events remote_users
                    can_join_remote_room_by_alias )],

   check => sub {
      my ( $GET_new_events, $remote_users ) = @_;

      $GET_new_events->( "m.presence",
         timeout => 50,
      )->then( sub {
         my %found_user;
         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( type content ));
            json_keys_ok( my $content = $event->{content}, qw( user_id presence ));

            $found_user{$content->{user_id}}++;
         }

         $found_user{$_->user_id} or die "Failed to find presence of ${\$_->user_id}"
            for @$remote_users;

         Future->done(1);
      });
   };
