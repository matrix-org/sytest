push our @EXPORT, qw( matrix_advance_receipt );

=head2 matrix_advance_receipt

   matrix_advance_receipt( $user, $room_id, $receipt_type, $event_id )->get;

Update the postion of the up-to-here receipt marker for a room.

=cut

#TODO This should go with the acuatal receipt tests when they exists.
sub matrix_advance_receipt
{
   my ( $user, $room_id, $receipt_type, $event_id ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/v2_alpha/rooms/$room_id/receipt/$receipt_type/$event_id",
      content => {}
   );
}


test "Read receipts appear in initial v2 /sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $event_id );

      my $filter = {
         room => {
            state => { types => [] },
            timeline => { types => [] },
            ephemeral => { types => ["m.receipt"] },
         },
         presence => { types => [] },
      };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "hello" );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_advance_receipt( $user, $room_id, "m.read", $event_id );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};

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
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $event_id, $next_batch );

      my $filter = {
         room => {
            state => { types => [] },
            timeline => { types => [] },
            ephemeral => { types => ["m.receipt"] },
         },
         presence => { types => [] },
      };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_send_room_text_message( $user, $room_id, body => "hello" );
      })->then( sub {
         ( $event_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};

         matrix_advance_receipt( $user, $room_id, "m.read", $event_id );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next_batch );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};

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
