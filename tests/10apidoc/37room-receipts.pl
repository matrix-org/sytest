test "POST /rooms/:room_id/receipt can create receipts",
   requires => [ local_user_and_room_fixtures() ],

   proves => [qw( can_post_room_receipts )],

   do => sub {
      my ( $user, $room_id ) = @_;

      # We need an event ID in the room. The ID of our own member event seems
      # reasonable. Lets fetch it.
      matrix_get_my_member_event( $user, $room_id )->then( sub {
         my ( $member_event ) = @_;
         my $event_id = $member_event->{event_id};

         do_request_json_for( $user,
            method => "POST",
            uri    => "/v2_alpha/rooms/$room_id/receipt/m.read/$event_id",

            content => {},
         );
      })->then_done(1);
   };

push our @EXPORT, qw( matrix_advance_room_receipt );

sub matrix_advance_room_receipt
{
   my ( $user, $room_id, $type, $event_id ) = @_;

   do_request_json_for( $user,
      method => "POST",
      uri    => "/v2_alpha/rooms/$room_id/receipt/$type/$event_id",

      content => {},
   )->then_done();
}
