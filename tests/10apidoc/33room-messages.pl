my $msgtype = "m.message";
my $body = "Here is the message content";

test "POST /rooms/:room_id/send/:event_type sends a message",
   requires => [qw( do_request_json_authed room_id )],

   do => sub {
      my ( $do_request_json_authed, $room_id ) = @_;

      $do_request_json_authed->(
         method => "POST",
         uri    => "/rooms/$room_id/send/$msgtype",

         content => {
            msgtype => $msgtype,
            body    => $body,
         },
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( event_id ));
         json_nonempty_string_ok( $body->{event_id} );

         provide can_send_message => 1;

         Future->done(1);
      });
   };

test "GET /events sees my sent message",
   requires => [qw( GET_new_events room_id user_id can_send_message )],

   check => sub {
      my ( $GET_new_events, $room_id, $user_id ) = @_;

      $GET_new_events->( "m.message" )->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( room_id user_id type content ));

            next unless $event->{room_id} eq $room_id;
            next unless $event->{user_id} eq $user_id;

            $found++;

            json_keys_ok( $event->{content}, qw( msgtype body ));

            $event->{content}{msgtype} eq $msgtype or die "Expected msgtype as $msgtype";
            $event->{content}{body} eq $body or die "Expected body as '$body'";
         }

         $found or
            die "Failed to find expected m.message event";

         Future->done(1);
      });
   };

test "GET /events as other user sees sent message",
   requires => [qw( GET_new_events_for_user room_id user_id more_users
                    can_send_message )],

   check => sub {
      my ( $GET_new_events_for_user, $room_id, $user_id, $more_users ) = @_;
      my $user = $more_users->[0];

      $GET_new_events_for_user->( $user, "m.message" )->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( room_id user_id type content ));

            next unless $event->{room_id} eq $room_id;
            next unless $event->{user_id} eq $user_id;

            $found++;

            json_keys_ok( $event->{content}, qw( msgtype body ));

            $event->{content}{msgtype} eq $msgtype or die "Expected msgtype as $msgtype";
            $event->{content}{body} eq $body or die "Expected body as '$body'";
         }

         $found or
            die "Failed to find expected m.message event";

         Future->done(1);
      });
   };
