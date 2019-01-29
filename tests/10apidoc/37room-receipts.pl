use URI::Escape::XS qw( uri_escape );

test "POST /rooms/:room_id/receipt can create receipts",
   requires => [ local_user_and_room_fixtures() ],

   proves => [qw( can_post_room_receipts )],

   do => sub {
      my ( $user, $room_id ) = @_;

      # We need an event ID in the room. The ID of our own member event seems
      # reasonable. Lets fetch it.
      matrix_get_my_member_event( $user, $room_id )->then( sub {
         my ( $member_event ) = @_;
         my $event_id = uri_escape( $member_event->{event_id} );

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/rooms/$room_id/receipt/m.read/$event_id",

            content => {},
         );
      })->then_done(1);
   };

push our @EXPORT, qw( matrix_advance_room_receipt matrix_advance_room_receipt_synced );

sub matrix_advance_room_receipt
{
   my ( $user, $room_id, $type, $event_id ) = @_;

   $event_id = uri_escape( $event_id );

   do_request_json_for( $user,
      method => "POST",
      uri    => "/r0/rooms/$room_id/receipt/$type/$event_id",

      content => {},
   )->then_done();
}

sub matrix_advance_room_receipt_synced
{
   my ( $user, $room_id, $type, $event_id ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
          matrix_advance_room_receipt( $user, $room_id, $type, $event_id );
      },
      check => sub {
         sync_room_contains( $_[0], $room_id, "ephemeral", sub {
            my ( $receipt ) = @_;

            log_if_fail "Receipt", $receipt;
            $receipt->{type} eq "m.receipt" and
               defined $receipt->{content}{$event_id}{$type}{ $user->user_id };
         });
      },
   );
}
