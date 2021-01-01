use Future::Utils qw( repeat );

push our @EXPORT, qw(
   matrix_do_and_wait_for_sync
   sync_room_contains
   sync_timeline_contains
   await_sync
   await_sync_timeline_contains
   await_sync_ephemeral_contains
   await_sync_timeline_or_state_contains
   await_sync_presence_contains
);

=head2 matrix_do_and_wait_for_sync

   my ( $action_result, $check_result ) = matrix_do_and_wait_for_sync( $user,
      do => sub {
         return some_action_that_returns_a_future();
      },
      check => sub {
         my ( $sync_body, $action_result ) = @_;

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

      $finished->then( sub {
         my ( @check_result ) = @_;
         Future->done( @action_result, @check_result );
      } );
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

sub sync_ephemeral_contains
{
   my ( $sync_body, $room_id, $check ) = @_;

   sync_room_contains( $sync_body, $room_id, "ephemeral", $check );
}

sub sync_presence_contains
{
   my ( $sync_body, $check ) = @_;

   return any { $check->( $_ ) } @{ $sync_body->{presence}{events} };
}

=head2 await_sync

   my ( $check_result ) = await_sync( $user,
      check => sub {
         my ( $sync_body ) = @_;

         # return a true value if the sync matches.
         # return a false value if the sync isn't ready yet.
         return check_that_sync_body_is_ready( $sync_body );
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

    $sync_body = await_sync_timeline_contains( $user, $room_id,
        check => sub {
            my ( $event ) = @_;
            return true_if_event_matches();
        },
    )->get();

Waits for something to appear in a the timeline of a particular room.
Returns the sync body.

The C<check> function gets given individual events.

See L</await_sync> for details of the C<since> parameter.

=cut

sub await_sync_timeline_contains {
   my ( $user, $room_id, %params ) = @_;

   my $check = delete $params{check} or die "Must supply a 'check' param";

   return await_sync( $user,
      check => sub {
         my ( $body ) = @_;

         return sync_timeline_contains( $body, $room_id, $check ) ? $body : 0;
      },
      %params,
   )
}

=head2 await_sync_ephemeral_contains

    $sync_body = await_sync_ephemeral_contains( $user, $room_id,
        check => sub {
            my ( $event ) = @_;
            return true_if_event_matches();
        },
    )->get();

Waits for something to appear in a the ephemeral section of a particular room.
Returns the sync body.

The C<check> function gets given individual events.

See L</await_sync> for details of the C<since> parameter.

=cut

sub await_sync_ephemeral_contains {
   my ( $user, $room_id, %params ) = @_;

   my $check = delete $params{check} or die "Must supply a 'check' param";

   return await_sync( $user,
      check => sub {
         my ( $body ) = @_;

         return sync_ephemeral_contains( $body, $room_id, $check ) ? $body : 0;
      },
      %params,
   )
}

=head2 await_sync_timeline_or_state_contains

    $sync_body = await_sync_timeline_or_state_contains( $user, $room_id,
        check => sub {
            my ( $event ) = @_;
            return true_if_event_matches();
        },
    )->get();

Waits for something to appear in a the timeline of a particular room.
Returns the sync body.

The C<check> function gets given individual events.

See L</await_sync> for details of the C<since> parameter.

=cut

sub await_sync_timeline_or_state_contains {
   my ( $user, $room_id, %params ) = @_;

   my $check = delete $params{check} or die "Must supply a 'check' param";

   return await_sync( $user,
      check => sub {
         my ( $body ) = @_;

         return (
            sync_timeline_contains( $body, $room_id, $check ) || sync_room_contains( $body, $room_id, "state", $check )
         ) ? $body : 0;
      },
      %params,
   )
}

=head2 await_sync_presence_contains

    $sync_body = await_sync_presence_contains( $user,
        check => sub {
            my ( $presence_event ) = @_;
            return true_if_event_matches();
        },
    )->get();

Waits for presence events to come down sync.
Returns the sync body.

The C<check> function gets given individual presence events.

See L</await_sync> for details of the C<since> parameter.

=cut

sub await_sync_presence_contains {
   my ( $user, %params ) = @_;

   my $check = delete $params{check} or die "Must supply a 'check' param";

   return await_sync( $user,
      check => sub {
         my ( $body ) = @_;

         return sync_presence_contains( $body, $check ) ? $body : 0;
      },
      %params,
   )
}


=head2 assert_state_types_match

Assert that the state body of a sync response is made up of the given state types.

$state is an arrayref of state events.

$state_types is an arrayref of arrayrefs, each a tuple of type & state_key, e.g:

   [
      [ 'm.room.create', '' ],
      [ 'm.room.name', '' ],
      [ 'm.room.member', '@foo:bar.com' ],
   ]

=cut

push @EXPORT, qw( assert_state_types_match );

sub assert_state_types_match {
   my ( $state, $room_id, $state_types ) = @_;

   my $found_types = [];
   foreach (@$state) {
      push @$found_types, [ $_->{type}, $_->{state_key} ];
   }

   my $comp = sub {
      return ($a->[0] cmp $b->[0]) || ($a->[1] cmp $b->[1]);
   };

   $found_types = [ sort $comp @$found_types ];
   $state_types = [ sort $comp @$state_types ];

   log_if_fail "Found state types", $found_types;
   log_if_fail "Desired state types", $state_types;

   assert_deeply_eq($found_types, $state_types);
}

=head2 assert_room_members

Assert that the given members are in the body of a sync response

$memberships is either an arrayref of user_ids or a hashref of user_id
to membership strings.

=cut

push @EXPORT, qw ( assert_room_members );

sub assert_room_members {
   my ( $body, $room_id, $memberships ) = @_;

   my $room = $body->{rooms}{join}{$room_id};
   my $timeline = $room->{timeline}{events};

   #log_if_fail "Room", $room;

   assert_json_keys( $room, qw( timeline state ephemeral ));

   return assert_state_room_members_match( $room->{state}{events}, $memberships );
}

=head2 assert_state_room_members_match

Assert that the given members are present in a block of state events

$memberships is either an arrayref of user_ids or a hashref of user_id
to membership strings.

=cut

push @EXPORT, qw( assert_state_room_members_match );

sub assert_state_room_members_match {
   my ( $events, $memberships ) = @_;

   log_if_fail "assert_state_room_members_match: expected members:", $memberships;
   log_if_fail "assert_state_room_members_match: actual state:", $events;

   my ( $member_ids );
   if ( ref($memberships) eq 'ARRAY' ) {
      $member_ids = $memberships;
      $memberships = {};
      foreach (@$member_ids) {
         $memberships->{$_} = 'join';
      }
   }
   else {
      $member_ids = [ keys %$memberships ];
   }

   my @members = grep { $_->{type} eq 'm.room.member' } @{ $events };
   @members == scalar @{ $member_ids }
      or die "Expected only ".(scalar @{ $member_ids })." membership events";

   my $found_senders = {};
   my $found_state_keys = {};

   foreach my $event (@members) {
      $event->{type} eq "m.room.member"
         or die "Unexpected state event type";

      assert_json_keys( $event, qw( sender state_key content ));

      $found_senders->{ $event->{sender} }++;
      $found_state_keys->{ $event->{state_key} }++;

      assert_json_keys( my $content = $event->{content}, qw( membership ));

      $content->{membership} eq $memberships->{ $event->{state_key} } or
         die "Expected membership as " . $memberships->{ $event->{state_key} };
   }

   foreach my $user_id (@{ $member_ids }) {
      assert_eq( $found_senders->{ $user_id }, 1,
                 "Expected membership event sender for ".$user_id );
      assert_eq( $found_state_keys->{ $user_id }, 1,
                 "Expected membership event state key for ".$user_id );
   }
}
