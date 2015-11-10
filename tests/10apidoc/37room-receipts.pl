test "POST /rooms/:room_id/receipt can create receipts",
   requires => [ local_user_and_room_fixtures() ],

   provides => [qw( can_post_room_receipts )],

   do => sub {
      my ( $user, $room_id ) = @_;

      # We need an event ID in the room. The ID of our own member event seems
      # reasonable. Lets fetch it.
      #
      # TODO: currently have to go the long way around finding it; see SPEC-264
      matrix_get_room_state( $user, $room_id )->then( sub {
         my ( $state ) = @_;

         my $member_event = first {
            $_->{type} eq "m.room.member" and $_->{state_key} eq $user->user_id
         } @$state;

         my $event_id = $member_event->{event_id};

         do_request_json_for( $user,
            method => "POST",
            uri    => "/v2_alpha/rooms/$room_id/receipt/m.read/$event_id",

            content => {},
         );
      })->then( sub {
         provide can_post_room_receipts => 1;

         push our @EXPORT, qw( matrix_advance_room_receipt );

         Future->done(1);
      });
   };

sub matrix_advance_room_receipt
{
   my ( $user, $room_id, $type, $event_id ) = @_;

   do_request_json_for( $user,
      method => "POST",
      uri    => "/v2_alpha/rooms/$room_id/receipt/$type/$event_id",

      content => {},
   )->then_done();
}
