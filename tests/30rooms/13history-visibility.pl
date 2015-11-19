push our @EXPORT, qw( matrix_set_room_history_visibility );

sub matrix_set_room_history_visibility
{
   my ( $user, $room_id, $history_visibility ) = @_;

   matrix_put_room_state( $user, $room_id,
      type    => "m.room.history_visibility",
      content => { history_visibility => $history_visibility }
   );
}

use constant { YES => 1, NO => 0 };

my %PERMITTED_ACTIONS = (
   # Map from the m.room.history_visibility state to a list of booleans,
   #   indicating what actions are/are not permitted
   shared => {
      see_before_join  => YES,
      see_after_invite => YES,
   },
   invited => {
      see_before_join  => NO,
      see_after_invite => YES,
   },
   joined => {
      see_before_join  => NO,
      see_after_invite => NO,
   },
);

sub test_history_visibility
{
   my ( $visibility, $permitted ) = @_;

   test "m.room.history_visibility == \"$visibility\" allows/forbids appropriately",
      requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

      do => sub {
         my ( $creator, $room_id, $joiner ) = @_;

         my $before_join_event_id;
         my $after_invite_event_id;

         matrix_set_room_history_visibility( $creator, $room_id, $visibility )
         ->then( sub {
            matrix_send_room_text_message( $creator, $room_id, body => "Before join" )
               ->on_done( sub { ( $before_join_event_id ) = @_ } )
         })->then( sub {
            matrix_invite_user_to_room( $creator, $joiner, $room_id );
         })->then( sub {
            matrix_send_room_text_message( $creator, $room_id, body => "After invite" )
               ->on_done( sub { ( $after_invite_event_id ) = @_ } )
         })->then( sub {
            matrix_join_room( $joiner, $room_id );
         })->then( sub {
            matrix_get_room_messages( $joiner, $room_id, limit => 10 )
         })->then( sub {
            my ( $body ) = @_;
            my %visible_events = map { $_->{event_id} => $_ } @{ $body->{chunk} };

            log_if_fail "Visible", [ keys %visible_events ];

            # TODO: this wants to use is()
            exists $visible_events{$before_join_event_id} == $permitted->{see_before_join} or
               die "Visibility of 'before_join' is unexpected";
            exists $visible_events{$after_invite_event_id} == $permitted->{see_after_invite} or
               die "Visibility of 'after_invite' is unexpected";

            Future->done(1);
         });
      };
}

foreach my $visibility (qw( shared invited joined )) {
   test_history_visibility( $visibility, $PERMITTED_ACTIONS{$visibility} );
}
