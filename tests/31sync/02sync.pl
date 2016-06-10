use Future::Utils qw( repeat );

push our @EXPORT, qw(
   matrix_do_and_wait_for_sync
   matrix_send_room_text_message_synced
   matrix_send_room_message_synced
   matrix_create_room_synced
   matrix_join_room_synced
   matrix_leave_room_synced
   matrix_invite_user_to_room_synced
   matrix_put_room_state_synced
   matrix_advance_room_receipt_synced
   sync_timeline_contains
);

=head2 matrix_do_and_wait_for_sync

   my ( $action_result ) = matrix_do_and_wait_for_sync( $user,
      do => sub {
         return some_action_that_returns_a_future();
      },
      check => sub {
         my ( $sync_body, $action_result ) = @_

         # return a true value if the sync contains the action.
         # return a false value if the sync isn't ready yet.
         return check_that_action_result_appears_in_sync_body(
            $sync_body, $action_result
         );
      },
   )->get;


Does something and waits for the result to appear in an incremental sync.
Doesn't affect the next_batch token used by matrix_sync_again.

The C<do> parameter is a subroutine with the action to perform that returns
a future.
The C<check> parameter is a subroutine that receives the body of an incremental
sync and the result of performing the action. The check subroutine returns
a true value if the incremental sync contains the result of the action, or a
false value if the incremental sync does not.

=cut

sub matrix_do_and_wait_for_sync
{
   my ( $user, %params ) = @_;

   my $check = delete $params{check} or die "Must supply a 'check' param";
   my $do = delete $params{do} or die "Must supply a 'do' param";
   $params{timeout} = $params{timeout} // 1000;

   my $next_batch;

   matrix_sync( $user,
      filter            => '{"room":{"rooms":[]},"account_data":{"types":[]},"presence":{"types":[]}}',
      update_next_batch => 0,
      set_presence      => "offline",
   )->then( sub {
      my ( $body ) = @_;

      $next_batch = $body->{next_batch};

      $do->();
   })->then( sub {
      my @action_result = @_;

      my $finished = repeat {
            matrix_sync( $user,
               %params,
               since             => $next_batch,
               update_next_batch => 0,
               set_presence      => "offline",
            )->then( sub {
               my ( $body ) = @_;

               $next_batch = $body->{next_batch};

               Future->done( $check->( $body, @action_result ) );
            });
         }
         until => sub {
            $_[0]->failure or $_[0]->get
         };

      $finished->then( sub { Future->done( @action_result ); } );
   });
}

sub sync_room_contains
{
   my ( $sync_body, $room_id, $section, $check ) = @_;

   my $room =  $sync_body->{rooms}{join}{$room_id};

   return any { $check->( $_ ) } @{ $room->{$section}{events} };
}

sub sync_timeline_contains
{
   my ( $sync_body, $room_id, $check ) = @_;

   sync_room_contains( $sync_body, $room_id, "timeline", $check );
}

sub matrix_send_room_text_message_synced
{
   my ( $user, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_send_room_text_message( $user, $room_id, %params );
      },
      check => sub {
         my ( $sync_body, $event_id ) = @_;

         sync_timeline_contains( $sync_body, $room_id, sub {
            $_[0]->{event_id} eq $event_id
         });
      },
   );
}

sub matrix_send_room_message_synced
{
   my ( $user, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_send_room_message( $user, $room_id, %params );
      },
      check => sub {
         my ( $sync_body, $event_id ) = @_;

         sync_timeline_contains( $sync_body, $room_id, sub {
            $_[0]->{event_id} eq $event_id
         });
      },
   );
}

sub matrix_create_room_synced
{
   my ( $user, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_create_room( $user, %params );
      },
      check => sub { exists $_[0]->{rooms}{join}{$_[1]} },
   );
}

sub matrix_join_room_synced
{
   my ( $user, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_join_room( $user, $room_id, %params );
      },
      check => sub { exists $_[0]->{rooms}{join}{$room_id} },
   );
}

sub matrix_leave_room_synced
{
   my ( $user, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_leave_room( $user, $room_id, %params );
      },
      check => sub { exists $_[0]->{rooms}{leave}{$room_id} },
   );
}

sub matrix_put_room_state_synced
{
   my ( $user, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_put_room_state( $user, $room_id, %params );
      },
      check => sub {
         my ( $sync_body, $put_result ) = @_;
         my $event_id = $put_result->{event_id};

         sync_timeline_contains( $sync_body, $room_id, sub {
            $_[0]->{event_id} eq $event_id;
         });
      },
   );
}

sub matrix_invite_user_to_room_synced
{
   my ( $inviter, $invitee, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $inviter,
      do => sub {
         matrix_do_and_wait_for_sync( $invitee,
            do => sub {
               matrix_invite_user_to_room(
                  $inviter, $invitee, $room_id, %params
               );
            },
            check => sub { exists $_[0]->{rooms}{invite}{$room_id} },
         );
      },
      check => sub {
         sync_timeline_contains( $_[0], $room_id, sub {
            $_[0]->{type} eq "m.room.member"
               and $_[0]->{state_key} eq $invitee->user_id
               and $_[0]->{content}{membership} eq "invite"
         });
      },
   );
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


test "Can sync",
    requires => [ local_user_fixture( with_events => 0 ),
                  qw( can_create_filter )],

    proves => [qw( can_sync )],

    do => sub {
       my ( $user ) = @_;

       my $filter_id;

       matrix_create_filter( $user, {} )->then( sub {
          ( $filter_id ) = @_;

          matrix_sync( $user, filter => $filter_id )
       })->then( sub {
          my ( $body ) = @_;

          matrix_sync( $user,
             filter => $filter_id,
             since => $body->{next_batch},
          )
       })->then_done(1);
    };
