prepare "Flushing event streams",
   requires => [qw( flush_events_for local_users )],
   do => sub {
      my ( $flush_events_for, $users ) = @_;

      Future->needs_all( map { $flush_events_for->( $_ ) } @$users );
   };

my $msgtype = "m.message";
my $msgbody = "Room message for 33room-messages";

test "Local room members see posted message events",
   requires => [qw( do_request_json await_event_for local_users room_id
                    can_send_message )],

   provides => [qw( can_receive_room_message_locally )],

   do => sub {
      my ( $do_request_json, undef, undef, $room_id ) = @_;

      $do_request_json->(
         method => "POST",
         uri    => "/rooms/$room_id/send/m.room.message",

         content => { msgtype => $msgtype, body => $msgbody },
      );
   },

   await => sub {
      my ( undef, $await_event_for, $users, $room_id ) = @_;
      my ( $senduser ) = @$users;

      Future->needs_all( map {
         my $recvuser = $_;

         $await_event_for->( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";

            require_json_keys( $event, qw( type content room_id user_id ));
            require_json_keys( my $content = $event->{content}, qw( msgtype body ));

            return unless $event->{room_id} eq $room_id;

            $content->{msgtype} eq $msgtype or
               die "Expected msgtype as $msgtype";
            $content->{body} eq $msgbody or
               die "Expected body as '$msgbody'";
            $event->{user_id} eq $senduser->user_id or
               die "Expected sender user_id as ${\$senduser->user_id}\n";

            return 1;
         });
      } @$users )->on_done( sub {
         provide can_receive_room_message_locally => 1;
      });
   };

test "Local room members can get room messages",
   requires => [qw( do_request_json_for local_users room_id
                    can_send_message can_get_messages )],

   check => sub {
      my ( $do_request_json_for, $local_users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $do_request_json_for->( $user,
            method => "GET",
            uri    => "/rooms/$room_id/messages",

            params => { limit => 1, dir => "b" },
         )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( start end chunk ));
            require_json_list( my $chunk = $body->{chunk} );

            scalar @$chunk == 1 or
               die "Expected one message";

            my ( $event ) = @$chunk;

            require_json_keys( $event, qw( type room_id user_id content ));

            $event->{type} eq "m.room.message" or
               die "Expected type to be m.room.message";
            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";

            require_json_keys( my $content = $event->{content}, qw( msgtype body ));

            $content->{msgtype} eq $msgtype or
               die "Expected msgtype to be $msgtype";
            $content->{body} eq $msgbody or
               die "Expected body to be '$msgbody'";

            Future->done(1);
         });
      } @$local_users )
   };

test "Remote room members also see posted message events",
   requires => [qw( await_event_for user remote_users room_id
                    can_receive_room_message_locally )],

   await => sub {
      my ( $await_event_for, $senduser, $remote_users, $room_id ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         $await_event_for->( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";

            require_json_keys( $event, qw( type content room_id user_id ));
            require_json_keys( my $content = $event->{content}, qw( msgtype body ));

            return unless $event->{room_id} eq $room_id;

            $content->{msgtype} eq $msgtype or
               die "Expected msgtype as $msgtype";
            $content->{body} eq $msgbody or
               die "Expected body as '$msgbody'";
            $event->{user_id} eq $senduser->user_id or
               die "Expected sender user_id as ${\$senduser->user_id}\n";

            return 1;
         });
      } @$remote_users );
   };

test "Remote room members can get room messages",
   requires => [qw( do_request_json_for remote_users room_id
                    can_send_message can_get_messages )],

   check => sub {
      my ( $do_request_json_for, $remote_users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $do_request_json_for->( $user,
            method => "GET",
            uri    => "/rooms/$room_id/messages",

            params => { limit => 1, dir => "b" },
         )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( start end chunk ));
            require_json_list( my $chunk = $body->{chunk} );

            scalar @$chunk == 1 or
               die "Expected one message";

            my ( $event ) = @$chunk;

            require_json_keys( $event, qw( type room_id user_id content ));

            $event->{type} eq "m.room.message" or
               die "Expected type to be m.room.message";
            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";

            require_json_keys( my $content = $event->{content}, qw( msgtype body ));

            $content->{msgtype} eq $msgtype or
               die "Expected msgtype to be $msgtype";
            $content->{body} eq $msgbody or
               die "Expected body to be '$msgbody'";

            Future->done(1);
         });
      } @$remote_users )
   };
