use Future::Utils qw( repeat );

push our @EXPORT, qw(
   matrix_do_and_wait_for_sync
   matrix_send_room_text_message_and_wait_for_sync
   matrix_send_room_message_and_wait_for_sync
   matrix_create_room_and_wait_for_sync
   matrix_join_room_and_wait_for_sync
   matrix_leave_room_and_wait_for_sync
   matrix_invite_user_to_room_and_wait_for_sync
   matrix_put_room_state_and_wait_for_sync
   sync_timeline_contains
);

=head2 matrix_sync_until

   my ( $sync_body ) = matrix_sync_until( $user, %query_params, until => sub {
      my ( $sync_body ) = @_;

      if acceptable( $sync_body ) {
         return 1;
      } else {
         return 0;
      }
   )->get;

A convenient wrapper around L</matrix_again> which repeatedly calls /sync
until the contents of the response are acceptable.

=cut


sub matrix_do_and_wait_for_sync
{
   my ( $user, %params ) = @_;

   my $check = delete $params{check} or die "Must supply a 'check' param";
   my $do = delete $params{do} or die "Must supply a 'do' param";
   $params{timeout} = $params{timeout} // 1000;

   my $next_batch;

   matrix_sync( $user,
      filter => '{"room":{"rooms":[]},"account_data":{"types":[]},"presence":{"types":[]}}',
      update_next_batch => 0,
   )->then( sub {
      my ( $body ) = @_;

      $next_batch = $body->{next_batch};

      $do->();
   })->then( sub {
      my ( $action_result ) = @_;

      my $finished = repeat {
            matrix_sync( $user,
               %params,
               since             => $next_batch,
               update_next_batch => 0,
            )->then( sub {
               my ( $body ) = @_;

               $next_batch = $body->{next_batch};

               Future->done( $check->( $body, $action_result ) );
            });
         }
         until => sub {
            $_[0]->failure or $_[0]->get
         };

      $finished->then( sub { Future->done( $action_result ); } );
   });
}

sub sync_timeline_contains
{
   my ( $sync_body, $room_id, $check ) = @_;

   my $room =  $sync_body->{rooms}{join}{$room_id};

   foreach my $event ( @{ $room->{timeline}{events} } ) {
      if ( $check->( $event ) ) {
         return 1;
      }
   }

   return 0;
}

sub matrix_send_room_text_message_and_wait_for_sync
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

sub matrix_send_room_message_and_wait_for_sync
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

sub matrix_create_room_and_wait_for_sync
{
   my ( $user, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_create_room( $user, %params );
      },
      check => sub { exists $_[0]->{rooms}{join}{$_[1]} },
   );
}

sub matrix_join_room_and_wait_for_sync
{
   my ( $user, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_join_room( $user, $room_id, %params );
      },
      check => sub { exists $_[0]->{rooms}{join}{$room_id} },
   );
}

sub matrix_leave_room_and_wait_for_sync
{
   my ( $user, $room_id, %params ) = @_;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_leave_room( $user, $room_id, %params );
      },
      check => sub { exists $_[0]->{rooms}{leave}{$room_id} },
   );
}

sub matrix_put_room_state_and_wait_for_sync
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

sub matrix_invite_user_to_room_and_wait_for_sync
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
