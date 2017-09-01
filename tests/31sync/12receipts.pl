test "Read receipts appear in initial v2 /sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id );

      my $filter = {
         presence => { types => [] },
         room     => {
            state     => { types => [] },
            timeline  => { types => [] },
            ephemeral => { types => [ "m.receipt" ] },
         },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "hello" );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_advance_room_receipt_synced( $user, $room_id, "m.read", $event_id );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         my $ephemeral = $room->{ephemeral}{events};

         @{ $ephemeral } == 1 or die "Expected a m.receipt event";

         log_if_fail "Ephemeral:", $ephemeral;

         my $receipt = $ephemeral->[0];

         $receipt->{type} eq "m.receipt" or die "Unexpected event type";
         defined $receipt->{content}{$event_id}{"m.read"}{ $user->user_id }
            or die "Expected to see a receipt for ${\ $user->user_id }";

         Future->done(1);
      });
   };


test "New read receipts appear in incremental v2 /sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id, $event_id );

      my $filter = {
         presence => { types => [] },
         room     => {
            state     => { types => [] },
            timeline  => { types => [] },
            ephemeral => { types => [ "m.receipt" ] },
         },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "hello" );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_advance_room_receipt_synced(
            $user, $room_id, "m.read", $event_id
         );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         my $ephemeral = $room->{ephemeral}{events};

         @{ $ephemeral } == 1 or die "Expected a m.receipt event";

         log_if_fail "Ephemeral:", $ephemeral;

         my $receipt = $ephemeral->[0];

         $receipt->{type} eq "m.receipt" or die "Unexpected event type";
         defined $receipt->{content}{$event_id}{"m.read"}{ $user->user_id }
            or die "Expected to see a receipt for ${\ $user->user_id }";

         Future->done(1);
      });
   };
