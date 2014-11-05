prepare "Flushing event streams",
   requires => [qw( flush_events_for local_users )],
   do => sub {
      my ( $flush_events_for, $users ) = @_;

      Future->needs_all( map { $flush_events_for->( $_ ) } @$users );
   };

my $msgtype = "m.message";
my $body = "Room message for 33room-messages";

test "All room members see posted messages",
   requires => [qw( do_request_json GET_new_events_for local_users room_id
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
      my ( undef, $GET_new_events_for, $users, $room_id ) = @_;
      my ( $senduser ) = @$users;

      Future->needs_all( map {
         my $recvuser = $_;

         $GET_new_events_for->( $recvuser, "m.room.message",
            timeout => 50,
         )->then( sub {
            my $found;
            foreach my $event ( @_ ) {
               json_keys_ok( $event, qw( type content room_id user_id ));
               json_keys_ok( my $content = $event->{content}, qw( msgtype body ));

               next unless $event->{room_id} eq $room_id;

               $found++;

               $content->{msgtype} eq $msgtype or
                  die "Expected msgtype as $msgtype";
               $content->{body} eq $body or
                  die "Expected body as '$body'";
               $event->{user_id} eq $senduser->user_id or
                  die "Expected sender user_id as ${\$senduser->user_id}\n";
            }

            $found or
               die "Failed to find expected m.room.message event";

            Future->done(1);
         });
      } @$users );
   };
