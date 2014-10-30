prepare "More room members",
   requires => [qw( do_request_json_for flush_events_for more_users room_id
                    can_join_room_by_id )],

   do => sub {
      my ( $do_request_json_for, $flush_events_for, $more_users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $flush_events_for->( $user )->then( sub {
            $do_request_json_for->( $user,
               method => "POST",
               uri    => "/rooms/$room_id/join",

               content => {},
            );
         });
      } @$more_users );
   };

test "New room members see their own join event",
   requires => [qw( GET_new_events_for more_users room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $GET_new_events_for, $more_users, $room_id ) = @_;

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
      } @$more_users );
   };

test "New room members also see original members' presence",
   requires => [qw( saved_events_for user more_users
                    can_join_room_by_id )],

   # Currently this test fails due to a Synapse bug. May be related to
   #   SYN-72 or SYN-81
   expect_fail => 1,
   check => sub {
      my ( $saved_events_for, $first_user, $more_users ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $saved_events_for->( $user, "m.presence" )->then( sub {
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
      } @$more_users );
   };

test "Existing members see new members' join events",
   requires => [qw( GET_new_events_for user more_users room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $GET_new_events_for, $user, $more_users, $room_id ) = @_;

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
            for @$more_users;

         Future->done(1);
      });
   };

test "Existing members see new members' presence",
   requires => [qw( saved_events_for user more_users
                    can_join_room_by_id )],

   check => sub {
      my ( $saved_events_for, $user, $more_users ) = @_;

      $saved_events_for->( $user, "m.presence" )->then( sub {
         my %found_user;
         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( type content ));
            json_keys_ok( my $content = $event->{content}, qw( user_id presence ));

            $found_user{$content->{user_id}}++;
         }

         $found_user{$_->user_id} or die "Failed to find presence of ${\$_->user_id}"
            for @$more_users;

         Future->done(1);
      });
   };
