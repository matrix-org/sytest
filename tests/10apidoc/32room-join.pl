test "POST /rooms/:room_id/join can join a room",
   requires => [qw( first_http_client more_users room_id
                    can_initial_sync )],

   do => sub {
      my ( $http, $more_users, $room_id ) = @_;
      my $user = $more_users->[0];

      $http->do_request_json(
         method => "POST",
         uri    => "/rooms/$room_id/join",
         params => { access_token => $user->access_token },

         content => {},
      );
   },

   check => sub {
      my ( $http, $more_users, $room_id ) = @_;
      my $user = $more_users->[0];

      $http->do_request_json(
         method => "GET",
         uri    => "/initialSync",
         params => { access_token => $user->access_token },
      )->then( sub {
         my ( $body ) = @_;

         json_list_ok( $body->{rooms} );

         my $found;
         foreach my $room ( @{ $body->{rooms} } ) {
            json_keys_ok( $room, qw( room_id membership ));

            next unless $room->{room_id} eq $room_id;
            $found++;

            $room->{membership} eq "join" or die "Expected room membership to be 'join'";
         }

         $found or
            die "Failed to find expected room";

         provide can_join_room_by_id => 1;

         Future->done(1);
      });
   };

test "GET /events sees my join-by-ID event",
   requires => [qw( GET_new_events_for_user more_users room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $GET_new_events_for_user, $more_users, $room_id ) = @_;
      my $user = $more_users->[0];

      $GET_new_events_for_user->( $user, "m.room.member" )->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( room_id user_id content membership ));
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
   };

test "Events also sees room state",
   requires => [qw( saved_events_for_user more_users room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $saved_events_for_user, $more_users, $room_id ) = @_;
      my $user = $more_users->[0];

      $saved_events_for_user->( $user, qr/^m\.room\./ )->then( sub {
         my @events = @_;

         my %wanted = map { $_ => 0 } qw(
            create aliases power_levels join_rules
            add_state_level send_event_level ops_levels
         );

         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( type ));
            my ( $type ) = $event->{type} =~ m/^m\.room\.(.*)$/;

            exists $wanted{$type} or die "Was not expecting a $event->{type} event";

            # TODO: Ideally we'd only get one of each event down, but currently
            # it seems we receive two 'm.room.aliases' events
            $wanted{$type} and warn "Received $event->{type} multiple times";

            $wanted{$type}++;
         }

         my @unreceived = grep { !$wanted{$_} } keys %wanted;
         @unreceived and
            die "Did not receive the expected @unreceived events";

         Future->done(1);
      });
   };

test "GET /events sees user's join-by-ID event",
   requires => [qw( GET_new_events more_users room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $GET_new_events, $more_users, $room_id ) = @_;
      my $user = $more_users->[0];

      $GET_new_events->( "m.room.member" )->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( room_id user_id content membership ));
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
   };

test "POST /join/:room_alias can join a room",
   requires => [qw( first_http_client more_users room_id room_alias
                    can_initial_sync )],

   do => sub {
      my ( $http, $more_users, undef, $room_alias ) = @_;
      my $user = $more_users->[1];

      $http->do_request_json(
         method => "POST",
         uri    => "/join/$room_alias",
         params => { access_token => $user->access_token },

         content => {},
      );
   },

   check => sub {
      my ( $http, $more_users, $room_id ) = @_;
      my $user = $more_users->[1];

      $http->do_request_json(
         method => "GET",
         uri    => "/initialSync",
         params => { access_token => $user->access_token },
      )->then( sub {
         my ( $body ) = @_;

         json_list_ok( $body->{rooms} );

         my $found;
         foreach my $room ( @{ $body->{rooms} } ) {
            json_keys_ok( $room, qw( room_id membership ));

            next unless $room->{room_id} eq $room_id;
            $found++;

            $room->{membership} eq "join" or die "Expected room membership to be 'join'";
         }

         $found or
            die "Failed to find expected room";

         provide can_join_room_by_alias => 1;

         Future->done(1);
      });
   };

test "GET /events sees my join-by-alias event",
   requires => [qw( GET_new_events_for_user more_users room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $GET_new_events_for_user, $more_users, $room_id ) = @_;
      my $user = $more_users->[1];

      $GET_new_events_for_user->( $user, "m.room.member" )->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( room_id user_id content membership ));
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
   };

test "GET /events sees user's join-by-alias event",
   requires => [qw( GET_new_events more_users room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $GET_new_events, $more_users, $room_id ) = @_;
      my $user = $more_users->[1];

      $GET_new_events->( "m.room.member" )->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( room_id user_id content membership ));
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
   };
