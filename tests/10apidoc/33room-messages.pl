my $msgtype = "m.message";
my $body = "Here is the message content";

test "POST /rooms/:room_id/send/:event_type sends a message",
   requires => [qw( do_request_json room_id )],

   do => sub {
      my ( $do_request_json, $room_id ) = @_;

      $do_request_json->(
         method => "POST",
         uri    => "/rooms/$room_id/send/m.room.message",

         content => { msgtype => $msgtype, body => $body },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( event_id ));
         require_json_nonempty_string( $body->{event_id} );

         provide can_send_message => 1;

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/messages returns a message",
   requires => [qw( do_request_json room_id can_send_message )],

   check => sub {
      my ( $do_request_json, $room_id ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/rooms/$room_id/messages",

         # With no params this does "forwards from END"; i.e. nothing useful
         params => { dir => "b" },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( start end chunk ));
         require_json_list( $body->{chunk} );

         scalar @{ $body->{chunk} } > 0 or
            die "Expected some messages but got none at all\n";

         provide can_get_messages => 1;

         Future->done(1);
      });
   };
