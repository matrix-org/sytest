use Future::Utils qw( repeat );

push our @EXPORT, qw(
   matrix_do_and_wait_for_sync
   sync_room_contains
   sync_timeline_contains
   await_sync
   await_sync_timeline_contains
   await_sync_presence_contains
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
      filter            => '{"room":{"rooms":[]},"account_data":{},"presence":{"types":[]}}',
      update_next_batch => 0,
      set_presence      => "offline",
   )->then( sub {
      my ( $body ) = @_;

      $next_batch = $body->{next_batch};

      $do->();
   })->then( sub {
      my @action_result = @_;

      my $finished = await_sync( $user,
         since => $next_batch,
         check => sub {
            $check->( $_[0], @action_result );
         },
         %params
      );

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

sub sync_presence_contains
{
   my ( $sync_body, $check ) = @_;

   return any { $check->( $_ ) } @{ $sync_body->{presence}{events} };
}

=head2 await_sync

   my ( $action_result ) = await_sync( $user,
      check => sub {
         my ( $sync_body ) = @_

         # return a true value if the sync contains the action.
         # return a false value if the sync isn't ready yet.
         return check_that_action_result_appears_in_sync_body(
            $sync_body, $action_result
         );
      },
   )->get;


Waits for something to appear in the sync stream of the user.

The C<check> parameter is a subroutine that receives the body of an incremental
sync and the result of performing the action. The check subroutine returns
a true value if the incremental sync contains the result of the action, or a
false value if the incremental sync does not.

The C<since> parameter can be specified to give a particular starting stream
token. If not specified then it will default to using $user->sync_next_batch,
falling back to doing a full sync if that doesn't exist either.

=cut

sub await_sync {
   my ( $user, %params ) = @_;

   my $check = delete $params{check} or die "Must supply a 'check' param";
   $params{timeout} = $params{timeout} // 1000;

   my $next_batch = delete $params{since} // $user->sync_next_batch;
   if ( $next_batch ) {
      $params{since} = $next_batch;
   }

   repeat {
      matrix_sync( $user,
         %params,
         update_next_batch => 0,
         set_presence      => "offline",
      )->then( sub {
         my ( $body ) = @_;

         $params{since} = $body->{next_batch};

         Future->done( $check->( $body ) );
      });
   }
   until => sub {
      $_[0]->failure or $_[0]->get
   }
}

=head2 await_sync_timeline_contains

Waits for something to appear in a the timeline of a particular room, see
await_sync for details.

The C<check> function gets given individual events.

=cut

sub await_sync_timeline_contains {
   my ( $user, $room_id, %params ) = @_;

   my $check = delete $params{check} or die "Must supply a 'check' param";

   await_sync( $user,
      check => sub {
         my ( $body ) = @_;

         sync_timeline_contains( $body, $room_id, $check )
      },
      %params,
   )
}

=head2 await_sync_presence_contains

Waits for presence events to come down sync, see await_sync for details.

The C<check> function gets given individual presence events.

=cut

sub await_sync_presence_contains {
   my ( $user, %params ) = @_;

   my $check = delete $params{check} or die "Must supply a 'check' param";

   await_sync( $user,
      check => sub {
         my ( $body ) = @_;

         sync_presence_contains( $body, $check )
      },
      %params,
   )
}
