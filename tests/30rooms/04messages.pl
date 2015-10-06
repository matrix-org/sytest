my @local_members;

my $remote_preparer = remote_user_preparer();

my $room_preparer = preparer(
   requires => [qw( local_users ), $remote_preparer ],

   do => sub {
      my ( $local_users, $remote_user ) = @_;

      @local_members = @$local_users;

      matrix_create_and_join_room( [ @local_members, $remote_user ] )
   },
);

prepare "Flushing event streams",
   requires => [qw( local_users )],

   do => sub {
      my ( $users ) = @_;

      Future->needs_all( map { flush_events_for( $_ ) } @$users );
   };

my $msgtype = "m.message";
my $msgbody = "Room message for 33room-messages";

test "Local room members see posted message events",
   requires => [qw( user ), $room_preparer,
                qw( can_send_message )],

   provides => [qw( can_receive_room_message_locally )],

   do => sub {
      my ( $user, $room_id ) = @_;
      my ( $senduser ) = @local_members;

      matrix_send_room_message( $user, $room_id,
         content => { msgtype => $msgtype, body => $msgbody },
      )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_event_for( $recvuser, sub {
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
         } @local_members )
      })->on_done( sub {
         provide can_receive_room_message_locally => 1;
      });
   };

test "Fetching eventstream a second time doesn't yield the message again",
   requires => [qw( can_receive_room_message_locally )],

   check => sub {
      Future->needs_all( map {
         my $recvuser = $_;

         do_request_json_for( $recvuser,
            method => "GET",
            uri    => "/api/v1/events",
            params => {
               from    => $recvuser->eventstream_token,
               timeout => 0,
            },
         )->then( sub {
            my ( $body ) = @_;

            foreach my $event ( @{ $body->{chunk} } ) {
               next unless $event->{type} eq "m.room.message";
               my $content = $event->{content};

               $content->{body} eq $msgbody and
                  die "Expected not to recieve duplicate message\n";
            }

            Future->done;
         })
      } @local_members )->then_done(1);
   };

test "Local non-members don't see posted message events",
   requires => [ local_user_preparer(), $room_preparer, ],

   do => sub {
      my ( $nonmember, $room_id ) = @_;

      Future->wait_any(
         await_event_for( $nonmember, sub {
            my ( $event ) = @_;
            log_if_fail "Received event:", $event;

            return unless $event->{type} eq "m.room.message";

            require_json_keys( $event, qw( type content room_id user_id ));
            return unless $event->{room_id} eq $room_id;

            die "Nonmember received event about a room they're not a member of";
         }),

         # So as not to wait too long, give it 500msec to not arrive
         delay( 0.5 )->then_done(1),
      );
   };

test "Local room members can get room messages",
   requires => [ $room_preparer,
                 qw( can_send_message can_get_messages )],

   check => sub {
      my ( $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",

            params => { limit => 1, dir => "b" },
         )->then( sub {
            my ( $body ) = @_;
            log_if_fail "Body:", $body;

            require_json_keys( $body, qw( start end chunk ));
            require_json_list( my $chunk = $body->{chunk} );

            scalar @$chunk == 1 or
               die "Expected one message";

            my ( $event ) = @$chunk;

            require_json_keys( $event, qw( type room_id user_id content ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";

            Future->done(1);
         });
      } @local_members )
   };

test "Remote room members also see posted message events",
   requires => [qw( user ), $remote_preparer, $room_preparer,
                qw( can_receive_room_message_locally )],

   do => sub {
      my ( $senduser, $remote_user, $room_id ) = @_;

      await_event_for( $remote_user, sub {
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
   };

test "Remote room members can get room messages",
   requires => [ $remote_preparer, $room_preparer,
                 qw( can_send_message can_get_messages )],

   check => sub {
      my ( $remote_user, $room_id ) = @_;

      do_request_json_for( $remote_user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/messages",

         params => { limit => 1, dir => "b" },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( start end chunk ));
         require_json_list( my $chunk = $body->{chunk} );

         scalar @$chunk == 1 or
            die "Expected one message";

         my ( $event ) = @$chunk;

         require_json_keys( $event, qw( type room_id user_id content ));

         $event->{room_id} eq $room_id or
            die "Expected room_id to be $room_id";

         Future->done(1);
      });
   };
