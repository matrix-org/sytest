prepare "Flushing event streams",
   requires => [qw( flush_events_for local_users )],
   do => sub {
      my ( $flush_events_for, $users ) = @_;

      Future->needs_all( map { $flush_events_for->( $_ ) } @$users );
   };

my $msgtype = "m.message";
my $body = "Room message for 33room-messages";

test "Local room members see posted messages",
   requires => [qw( do_request_json await_event_for local_users room_id
                    can_send_message )],

   do => sub {
      my ( $do_request_json, undef, undef, $room_id ) = @_;

      $do_request_json->(
         method => "POST",
         uri    => "/rooms/$room_id/send/m.room.message",

         content => { msgtype => $msgtype, body => $body },
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

            json_keys_ok( $event, qw( type content room_id user_id ));
            json_keys_ok( my $content = $event->{content}, qw( msgtype body ));

            return unless $event->{room_id} eq $room_id;

            $content->{msgtype} eq $msgtype or
               die "Expected msgtype as $msgtype";
            $content->{body} eq $body or
               die "Expected body as '$body'";
            $event->{user_id} eq $senduser->user_id or
               die "Expected sender user_id as ${\$senduser->user_id}\n";

            return 1;
         });
      } @$users )->on_done( sub {
         provide can_receive_room_message_locally => 1;
      });
   };

test "Remote room members also see posted messages",
   requires => [qw( await_event_for user remote_users room_id
                    can_receive_room_message_locally )],

   await => sub {
      my ( $await_event_for, $senduser, $remote_users, $room_id ) = @_;

      Future->needs_all( map {
         my $recvuser = $_;

         $await_event_for->( $recvuser, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";

            json_keys_ok( $event, qw( type content room_id user_id ));
            json_keys_ok( my $content = $event->{content}, qw( msgtype body ));

            return unless $event->{room_id} eq $room_id;

            $content->{msgtype} eq $msgtype or
               die "Expected msgtype as $msgtype";
            $content->{body} eq $body or
               die "Expected body as '$body'";
            $event->{user_id} eq $senduser->user_id or
               die "Expected sender user_id as ${\$senduser->user_id}\n";

            return 1;
         });
      } @$remote_users );
   };
