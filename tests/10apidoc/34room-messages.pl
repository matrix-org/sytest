test "POST /rooms/:room_id/send/:event_type sends a message",
   requires => [ local_user_and_room_fixtures() ],

   proves => [qw( can_send_message )],

   do => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/send/m.room.message",

         content => { msgtype => "m.message", body => "Here is the message content" },
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( event_id ));
         assert_json_nonempty_string( $body->{event_id} );

         push our @EXPORT, qw(
            matrix_send_room_message matrix_send_room_text_message
         );

         Future->done(1);
      });
   };

sub matrix_send_room_message
{
   my ( $user, $room_id, %opts ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   defined $opts{content} or
      croak "Cannot matrix_send_room_message() with no content";

   my $type = $opts{type} // "m.room.message";

   my $method = "POST";
   my $uri = "/api/v1/rooms/$room_id/send/$type";

   if( defined $opts{txn_id} ) {
      $method = "PUT";
      $uri = "$uri/$opts{txn_id}";
   }

   do_request_json_for( $user,
      method => $method,
      uri    => $uri,
      content => $opts{content},
   )->then( sub {
      my ( $body ) = @_;

      Future->done( $body->{event_id} );
   });
}

# Further convenience for the majority of cases
sub matrix_send_room_text_message
{
   my ( $user, $room_id, %opts ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   defined $opts{body} or
      croak "Cannot matrix_send_room_text_message() with no body";

   matrix_send_room_message( $user, $room_id,
      content => {
         msgtype => $opts{msgtype} // "m.text",
         body    => $opts{body},
      },
      txn_id  => $opts{txn_id},
   )
}

test "GET /rooms/:room_id/messages returns a message",
   requires => [ local_user_and_room_fixtures(),
                 qw( can_send_message )],

   proves => [qw( can_get_messages )],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_send_room_text_message( $user, $room_id,
         body => "Here is the message content",
      )->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",

            # With no params this does "forwards from END"; i.e. nothing useful
            params => { dir => "b" },
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( start end chunk ));
         assert_json_list( $body->{chunk} );

         scalar @{ $body->{chunk} } > 0 or
            die "Expected some messages but got none at all\n";

         push our @EXPORT, qw( matrix_get_room_messages );

         Future->done(1);
      });
   };

sub matrix_get_room_messages
{
   my ( $user, $room_id, %params ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   $params{dir} ||= "b";

   do_request_json_for( $user,
      method => "GET",
      uri    => "/api/v1/rooms/$room_id/messages",

      params => \%params,
   );
}
