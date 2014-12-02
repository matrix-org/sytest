prepare "Flushing event streams",
   requires => [qw( flush_events_for local_users remote_users )],
   do => sub {
      my ( $flush_events_for, $local_users, $remote_users ) = @_;

      Future->needs_all( map { $flush_events_for->( $_ ) } @$local_users, @$remote_users );
   };

my $status_msg = "Update for room members";

test "Presence changes are reported to local room members",
   requires => [qw( do_request_json await_event_for local_users
                    can_set_presence can_create_room can_join_room_by_id )],

   do => sub {
      my ( $do_request_json, undef, undef ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/presence/:user_id/status",

         content => { presence => "online", status_msg => $status_msg },
      )
   },

   await => sub {
      my ( undef, $await_event_for, $users ) = @_;
      my ( $senduser ) = @$users;

      Future->needs_all( map {
         my $recvuser = $_;

         $await_event_for->( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";

            require_json_keys( $event, qw( type content ));
            require_json_keys( my $content = $event->{content}, qw( user_id presence status_msg ));

            $content->{user_id} eq $senduser->user_id or next;

            $content->{status_msg} eq $status_msg or
               die "Expected content status_msg to '$status_msg'";

            return 1;
         });
      } @$users );
   };

test "Presence changes are also reported to remote room members",
   requires => [qw( await_event_for user remote_users
                    can_set_presence can_create_room can_join_remote_room_by_alias )],

   await => sub {
      my ( $await_event_for, $senduser, $remote_users ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         $await_event_for->( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";

            require_json_keys( $event, qw( type content ));
            require_json_keys( my $content = $event->{content}, qw( user_id presence status_msg ));

            $content->{user_id} eq $senduser->user_id or next;

            $content->{status_msg} eq $status_msg or
               die "Expected content status_msg to '$status_msg'";

            return 1;
         });
      } @$remote_users );
   };
