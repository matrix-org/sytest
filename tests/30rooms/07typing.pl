use Time::HiRes qw( time );

prepare "Flushing event streams",
   requires => [qw( flush_events_for local_users remote_users )],
   do => sub {
      my ( $flush_events_for, $local_users, $remote_users ) = @_;

      Future->needs_all( map { $flush_events_for->( $_ ) } @$local_users, @$remote_users );
   };

# This file only operates on members of the room; so we'll just work out who of
# the local_users is still a member, so as not to be dependent on the actions
# of earlier tests.

my @local_members;
prepare "Fetching current room members",
   requires => [qw( do_request_json local_users room_id )],

   do => sub {
      my ( $do_request_json, $local_users, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state",
      )->then( sub {
         my ( $body ) = @_;

         my %members;
         $_->{type} eq "m.room.member" and $_->{content}{membership} eq "join" and
            $members{$_->{state_key}} = 1 for @$body;

         @local_members = grep { $members{$_->user_id} } @$local_users;

         Future->done(1);
      });
   };

test "Typing notification sent to local room members",
   requires => [qw( do_request_json await_event_for user room_id
                    can_set_room_typing can_create_room can_join_room_by_id )],

   do => sub {
      my ( $do_request_json, undef, undef, $room_id ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/typing/:user_id",

         content => { typing => 1, timeout => 30000 }, # msec
      );
   },

   await => sub {
      my ( undef, $await_event_for, $typinguser, $room_id ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         $await_event_for->( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.typing";

            require_json_keys( $event, qw( type room_id content ));
            require_json_keys( my $content = $event->{content}, qw( user_ids ));

            return unless $event->{room_id} eq $room_id;

            require_json_list( my $users = $content->{user_ids} );

            scalar @$users == 1 or
               die "Expected 1 member to be typing";
            $users->[0] eq $typinguser->user_id or
               die "Expected ${\$typinguser->user_id} to be typing";

            return 1;
         })
      } @local_members );
   };

test "Typing notifications also sent to remove room members",
   requires => [qw( await_event_for user remote_users room_id
                    can_set_room_typing can_create_room can_join_remote_room_by_alias )],

   await => sub {
      my ( $await_event_for, $typinguser, $remote_users, $room_id ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         $await_event_for->( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.typing";

            require_json_keys( $event, qw( type room_id content ));
            require_json_keys( my $content = $event->{content}, qw( user_ids ));

            return unless $event->{room_id} eq $room_id;

            require_json_list( my $users = $content->{user_ids} );

            scalar @$users == 1 or
               die "Expected 1 member to be typing";
            $users->[0] eq $typinguser->user_id or
               die "Expected ${\$typinguser->user_id} to be typing";

            return 1;
         })
      } @$remote_users );
   };

test "Typing can be explicitly stopped",
   requires => [qw( do_request_json await_event_for user room_id
                    can_set_room_typing can_create_room can_join_room_by_id )],

   do => sub {
      my ( $do_request_json, undef, undef, $room_id ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/typing/:user_id",

         content => { typing => 0 },
      );
   },

   await => sub {
      my ( undef, $await_event_for, $typinguser, $room_id ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         $await_event_for->( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.typing";

            require_json_keys( $event, qw( type room_id content ));
            require_json_keys( my $content = $event->{content}, qw( user_ids ));

            return unless $event->{room_id} eq $room_id;

            require_json_list( my $users = $content->{user_ids} );

            scalar @$users and
               die "Expected 0 members to be typing";

            return 1;
         })
      } @local_members );
   };

prepare "Flushing event streams",
   requires => [qw( flush_events_for remote_users )],
   do => sub {
      my ( $flush_events_for, $remote_users ) = @_;

      Future->needs_all( map { $flush_events_for->( $_ ) } @local_members, @$remote_users );
   };

multi_test "Typing notifications timeout and can be resent",
   requires => [qw( do_request_json await_event_for user room_id
                    can_set_room_typing can_create_room )],

   await => sub {
      my ( $do_request_json, $await_event_for, $user, $room_id ) = @_;

      my $start_time = time();

      $do_request_json->(
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/typing/:user_id",

         content => { typing => 1, timeout => 100 }, # msec; i.e. very short
      )->then( sub {
         pass( "Sent typing notification" );

         # start typing
         $await_event_for->( $user, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.typing";
            return unless $event->{room_id} eq $room_id;

            return unless scalar @{ $event->{content}{user_ids} };

            pass( "Received start notification" );
            return 1;
         })
      })->then( sub {
         # stop typing
         $await_event_for->( $user, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.typing";
            return unless $event->{room_id} eq $room_id;

            return if scalar @{ $event->{content}{user_ids} };

            ( time() - $start_time ) < 0.5 or
               die "Took too long to time out";

            pass( "Received stop notification" );
            return 1;
         })
      })->then( sub {
         $do_request_json->(
            method => "PUT",
            uri    => "/api/v1/rooms/$room_id/typing/:user_id",

            content => { typing => 1, timeout => 10000 },
         )
      })->then( sub {
         pass( "Sent second notification" );

         Future->done(1);
      });
   };
