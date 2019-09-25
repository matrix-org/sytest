test "POST /rooms/:room_id/read_markers can create read marker",
   requires => [ local_user_and_room_fixtures() ],

   proves => [qw( can_post_room_markers )],

   do => sub {
      my ( $user, $room_id ) = @_;

      # We need an event ID in the room. The ID of our own member event seems
      # reasonable. Lets fetch it.
      matrix_get_my_member_event( $user, $room_id )->then( sub {
         my ( $member_event ) = @_;
         my $event_id = $member_event->{event_id};

         do_request_json_for( $user,
            method => "POST",
            uri    => "/r0/rooms/$room_id/read_markers",

            content => {
               "m.fully_read" => $event_id,
            },
         );
      })->then_done(1);
   };


push our @EXPORT, qw( matrix_advance_room_read_marker matrix_advance_room_read_marker_synced );

sub matrix_advance_room_read_marker
{
   my ( $user, $room_id, $event_id ) = @_;

   do_request_json_for( $user,
      method => "POST",
      uri    => "/r0/rooms/$room_id/read_markers",

      content => {
         "m.fully_read" => $event_id,
      },
   )->then_done();
}

sub matrix_advance_room_read_marker_synced
{
   my ( $user, $room_id, $event_id ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
          matrix_advance_room_read_marker( $user, $room_id, $event_id );
      },
      check => sub {
         sync_room_contains( $_[0], $room_id, "account_data", sub {
            my ( $read_marker ) = @_;

            log_if_fail "Read marker", $read_marker;
            $read_marker->{type} eq "m.fully_read" and
               $read_marker->{content}{event_id} eq $event_id;
         });
      },
   );
}
