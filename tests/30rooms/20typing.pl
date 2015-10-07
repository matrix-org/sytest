use Time::HiRes qw( time );

prepare "Flushing event streams",
   requires => [qw( local_users remote_users )],
   do => sub {
      my ( $local_users, $remote_users ) = @_;

      Future->needs_all(
         map { flush_events_for( $_ ) } @$local_users, @$remote_users
      );
   };

my $room_id;
my @local_members;

prepare "Creating test room",
   requires => [qw( local_users remote_users )],

   do => sub {
      my ( $local_users, $remote_users ) = @_;

      @local_members = @$local_users;

      matrix_create_and_join_room( [ @$local_users, @$remote_users ] )
      ->on_done( sub {
         ( $room_id ) = @_;
      });
   };

test "Typing notification sent to local room members",
   requires => [qw( user
                    can_set_room_typing )],

   do => sub {
      my ( $typinguser ) = @_;

      do_request_json_for( $typinguser,
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/typing/:user_id",

         content => { typing => 1, timeout => 30000 }, # msec
      )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_event_for( $recvuser, sub {
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
      });
   };

test "Typing notifications also sent to remove room members",
   requires => [qw( user remote_users
                    can_set_room_typing can_join_remote_room_by_alias )],

   do => sub {
      my ( $typinguser, $remote_users ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         await_event_for( $recvuser, sub {
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
   requires => [qw( user
                    can_set_room_typing )],

   do => sub {
      my ( $typinguser ) = @_;

      do_request_json_for( $typinguser,
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/typing/:user_id",

         content => { typing => 0 },
      )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_event_for( $recvuser, sub {
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
      });
   };

multi_test "Typing notifications timeout and can be resent",
   requires => [qw( user
                    can_set_room_typing )],

   do => sub {
      my ( $user ) = @_;

      my $start_time = time();

      flush_events_for( $user )
      ->then( sub {
         do_request_json_for( $user,
            method => "PUT",
            uri    => "/api/v1/rooms/$room_id/typing/:user_id",

            content => { typing => 1, timeout => 100 }, # msec; i.e. very short
         )
      })->then( sub {
         pass( "Sent typing notification" );

         # start typing
         await_event_for( $user, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.typing";
            return unless $event->{room_id} eq $room_id;

            return unless scalar @{ $event->{content}{user_ids} };

            pass( "Received start notification" );
            return 1;
         })
      })->then( sub {
         # stop typing
         await_event_for( $user, sub {
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
         do_request_json_for( $user,
            method => "PUT",
            uri    => "/api/v1/rooms/$room_id/typing/:user_id",

            content => { typing => 1, timeout => 10000 },
         )
      })->then( sub {
         pass( "Sent second notification" );

         Future->done(1);
      });
   };
