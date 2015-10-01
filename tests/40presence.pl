my $room_id;

# Ensure all the users are members of a shared room, so that we know presence
# messages can be shared between them all
prepare "Creating a new test room",
   requires => [qw( make_test_room local_users remote_users )],

   do => sub {
      my ( $make_test_room, $local_users, $remote_users ) = @_;

      $make_test_room->( [ @$local_users, @$remote_users ] )
         ->on_done( sub {
            ( $room_id ) = @_;
         });
   };

prepare "Flushing event streams",
   requires => [qw( local_users remote_users )],
   do => sub {
      my ( $local_users, $remote_users ) = @_;

      Future->needs_all(
         map { flush_events_for( $_ ) } @$local_users, @$remote_users
      );
   };

my $status_msg = "Update for room members";

test "Presence changes are reported to local room members",
   requires => [qw( user local_users
                    can_set_presence can_join_room_by_id )],

   do => sub {
      my ( $user, undef ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/presence/:user_id/status",

         content => { presence => "online", status_msg => $status_msg },
      )
   },

   await => sub {
      my ( undef, $users ) = @_;
      my ( $senduser ) = @$users;

      Future->needs_all( map {
         my $recvuser = $_;

         await_event_for( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";

            require_json_keys( $event, qw( type content ));
            require_json_keys( my $content = $event->{content},
               qw( user_id presence ));

            $content->{user_id} eq $senduser->user_id or return;

            require_json_keys( $content, qw( status_msg ));

            $content->{status_msg} eq $status_msg or
               die "Expected content status_msg to '$status_msg'";

            return 1;
         });
      } @$users );
   };

test "Presence changes are also reported to remote room members",
   requires => [qw( user remote_users
                    can_set_presence can_join_remote_room_by_alias )],

   await => sub {
      my ( $senduser, $remote_users ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         await_event_for( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";

            require_json_keys( $event, qw( type content ));
            require_json_keys( my $content = $event->{content},
               qw( user_id presence ));

            # The next presence message we get might not necessarily be the
            # one we were expecting, given this is remote. Wait to get the
            # right one
            $content->{user_id} eq $senduser->user_id or return;

            $content->{status_msg} and $content->{status_msg} eq $status_msg
               or return;

            return 1;
         });
      } @$remote_users );
   };

test "Presence changes to OFFLINE are reported to local room members",
   requires => [qw( user local_users
                    can_set_presence can_join_room_by_id )],

   do => sub {
      my ( $user, undef ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/presence/:user_id/status",

         content => { presence => "offline" },
      )
   },

   await => sub {
      my ( undef, $users ) = @_;
      my ( $senduser ) = @$users;

      Future->needs_all( map {
         my $recvuser = $_;

         await_event_for( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";

            my $content = $event->{content};
            return unless $content->{user_id} eq $senduser->user_id;

            return unless $content->{presence} eq "offline";

            return 1;
         })
      } @$users );
   };

test "Presence changes to OFFLINE are reported to remote room members",
   requires => [qw( user remote_users
                    can_set_presence can_join_remote_room_by_alias )],

   await => sub {
      my ( $senduser, $remote_users ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         await_event_for( $recvuser, sub {
            my ( $event ) = @_;

            return unless $event->{type} eq "m.presence";

            my $content = $event->{content};
            return unless $content->{user_id} eq $senduser->user_id;

            return unless $content->{presence} eq "offline";

            return 1;
         });
      } @$remote_users );
   };

prepare "Leaving test room",
   requires => [qw( local_users remote_users )],

   do => sub {
      my ( $local_users, $remote_users ) = @_;

      Future->needs_all( map {
         my $user = $_;

         do_request_json_for( $user,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/leave",

            content => {},
         )
      } @$local_users, @$remote_users )
   };
