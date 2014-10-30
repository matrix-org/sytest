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

         json_keys_ok( $body, qw( event_id ));
         json_nonempty_string_ok( $body->{event_id} );

         provide can_send_message => 1;

         Future->done(1);
      });
   };
