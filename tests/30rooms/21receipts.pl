use List::Util qw( first );

test "Read receipts are visible to /initialSync",
   requires => [ local_user_and_room_preparers(),
                 qw( can_post_room_receipts )],

   do => sub {
      my ( $user, $room_id ) = @_;

      # We need an event ID in the room. The ID of our own member event seems
      # reasonable. Lets fetch it.
      my $event_id;

      # TODO: currently have to go the long way around finding it; see SPEC-264
      matrix_get_room_state( $user, $room_id )->then( sub {
         my ( $state ) = @_;

         my $member_event = first {
            $_->{type} eq "m.room.member" and $_->{state_key} eq $user->user_id
         } @$state;

         $event_id = $member_event->{event_id};

         matrix_advance_room_receipt( $user, $room_id, "m.read" => $event_id )
      })->then( sub {
         matrix_initialsync( $user )
      })->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( receipts ));
         require_json_list( my $receipts = $body->{receipts} );

         log_if_fail "initialSync receipts", $receipts;

         my ( $receipt ) = first {
            require_json_keys( $_, qw( room_id type ));
            $_->{room_id} eq $room_id and $_->{type} eq "m.receipt"
         } @$receipts;

         require_json_keys( $receipt, qw( content ));
         my $content = $receipt->{content};

         exists $content->{$event_id} or
            die "Expected to find an acknolwedgement of $event_id";
         exists $content->{$event_id}{"m.read"} or
            die "Expected an 'm.read' type receipt for this event";
         my $user_read_receipt = $content->{$event_id}{"m.read"}{ $user->user_id } or
            die "Expected an 'm.read' receipt from ${\ $user->user_id }";

         require_json_keys( $user_read_receipt, qw( ts ));
         require_json_number( $user_read_receipt->{ts} );

         Future->done(1);
      });
   };

test "Read receipts are sent as events",
   requires => [ local_user_and_room_preparers(),
                 qw( can_post_room_receipts )],

   do => sub {
      my ( $user, $room_id ) = @_;

      # We need an event ID in the room. The ID of our own member event seems
      # reasonable. Lets fetch it.
      my $event_id;

      # TODO: currently have to go the long way around finding it; see SPEC-264
      matrix_get_room_state( $user, $room_id )->then( sub {
         my ( $state ) = @_;

         my $member_event = first {
            $_->{type} eq "m.room.member" and $_->{state_key} eq $user->user_id
         } @$state;

         $event_id = $member_event->{event_id};

         matrix_advance_room_receipt( $user, $room_id, "m.read" => $event_id )
      })->then( sub {
         await_event_for( $user, sub {
            my ( $event ) = @_;

            return unless $event->{type} eq "m.receipt";

            require_json_keys( $event, qw( type room_id content ));
            return unless $event->{room_id} eq $room_id;

            log_if_fail "Event", $event;

            my $content = $event->{content};
            exists $content->{$event_id} or return;
            exists $content->{$event_id}{"m.read"} or return;
            my $user_read_receipt = $content->{$event_id}{"m.read"}{ $user->user_id } or
               return;

            require_json_keys( $user_read_receipt, qw( ts ));
            require_json_number( $user_read_receipt->{ts} );

            return 1;
         })
      });
   };
