my $senduser_fixture = local_user_fixture();

my $local_user_fixture = local_user_fixture();

my $remote_fixture = remote_user_fixture();

my $room_fixture = room_fixture(
   requires_users => [ $senduser_fixture, $local_user_fixture, $remote_fixture ],
);

my $msgtype = "m.message";
my $msgbody = "Room message for 33room-messages";

test "Local room members see posted message events",
   requires => [ $senduser_fixture, $local_user_fixture, $room_fixture,
                 qw( can_send_message )],

   provides => [qw( can_receive_room_message_locally )],

   do => sub {
      my ( $senduser, $local_user, $room_id ) = @_;

      matrix_send_room_message( $senduser, $room_id,
         content => { msgtype => $msgtype, body => $msgbody },
      )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_event_for( $recvuser, filter => sub {
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
         } $senduser, $local_user )
      })->on_done( sub {
         provide can_receive_room_message_locally => 1;
      });
   };

test "Fetching eventstream a second time doesn't yield the message again",
   requires => [ $senduser_fixture, $local_user_fixture,
                 qw( can_receive_room_message_locally )],

   check => sub {
      my ( $senduser, $local_user ) = @_;

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
      } $senduser, $local_user )->then_done(1);
   };

test "Local non-members don't see posted message events",
   requires => [ local_user_fixture(), $room_fixture, ],

   do => sub {
      my ( $nonmember, $room_id ) = @_;

      Future->wait_any(
         await_event_for( $nonmember, filter => sub {
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
   requires => [ $senduser_fixture, $local_user_fixture, $room_fixture,
                 qw( can_send_message can_get_messages )],

   check => sub {
      my ( $senduser, $local_user, $room_id ) = @_;

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
      } $senduser, $local_user )
   };

test "Remote room members also see posted message events",
   requires => [ $senduser_fixture, $remote_fixture, $room_fixture,
                qw( can_receive_room_message_locally )],

   do => sub {
      my ( $senduser, $remote_user, $room_id ) = @_;

      await_event_for( $remote_user, filter => sub {
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
   requires => [ $remote_fixture, $room_fixture,
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
