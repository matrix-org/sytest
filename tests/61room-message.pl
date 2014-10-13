test "A user can send a message to a room",
   requires => [qw( first_room )],

   do => sub {
      my ( $ROOM ) = @_;

      $ROOM->send_message( "Here is a message" )
   },

   wait_time => 3,
   check => sub {
      my ( $ROOM ) = @_;

      my ( $member, $content ) = @{ $ROOM->last_message };

      $content->{msgtype} eq "m.text" or
         return Future->fail( "Message content type is incorrect" );

      $content->{body} eq "Here is a message" or
         return Future->fail( "Message content body is incorrect" );

      provide room_message => 1;
      Future->done(1);
   },

   provides => [qw( room_message )];

test "Other users can see messages sent to a room",
   requires => [qw( rooms room_message )],

   wait_time => 3,
   check => sub {
      my ( $ROOMS ) = @_;
      my ( undef, @other_rooms ) = @$ROOMS;

      foreach my $room ( @other_rooms ) {
         my ( $member, $content ) = @{ $room->last_message };

         $content->{msgtype} eq "m.text" or
            return Future->fail( "Message content type is incorrect" );

         $content->{body} eq "Here is a message" or
            return Future->fail( "Message content body is incorrect" );
      }

      Future->done(1);
   },
