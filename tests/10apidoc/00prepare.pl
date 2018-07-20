our @EXPORT = qw( User is_User do_request_json_for new_User assert_room_members assert_room_members_in_state );

my @KEYS = qw(
   http user_id device_id password access_token eventstream_token
   sync_next_batch saved_events pending_get_events device_message_next_batch
);

# A handy little structure for other scripts to find in 'user' and 'more_users'
struct User => [ @KEYS ], predicate => 'is_User';

sub do_request_json_for
{
   my ( $user, %args ) = @_;
   is_User( $user ) or croak "Expected a User";

   my $user_id = $user->user_id;
   ( my $uri = delete $args{uri} ) =~ s/:user_id/$user_id/g;

   my %params = (
      access_token => $user->access_token,
      %{ delete $args{params} || {} },
   );

   $user->http->do_request_json(
      uri          => $uri,
      params       => \%params,
      request_user => $user->user_id,
      %args,
   );
}


sub new_User
{
   my ( %params ) = @_;

   my $user = User( delete @params{ @KEYS } );

   if ( %params ) {
      die "Unexpected parameter to new_User";
   }

   return $user;
}


# assert that the given members are in the body of a sync response
sub assert_room_members {
   my ( $body, $room_id, $member_ids ) = @_;

   my $room = $body->{rooms}{join}{$room_id};
   my $timeline = $room->{timeline}{events};

   log_if_fail "Room", $room;

   assert_json_keys( $room, qw( timeline state ephemeral ));

   return assert_room_members_in_state( $room->{state}{events}, $member_ids );
}


# assert that the given members are present in a block of state events
sub assert_room_members_in_state {
   my ( $events, $member_ids ) = @_;

   log_if_fail "members:", $member_ids;
   log_if_fail "state:", $events;

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

      $content->{membership} eq "join" or
         die "Expected membership as 'join'";
   }

   foreach my $user_id (@{ $member_ids }) {
      assert_eq( $found_senders->{ $user_id }, 1,
                 "Expected membership event sender for ".$user_id );
      assert_eq( $found_state_keys->{ $user_id }, 1,
                 "Expected membership event state key for ".$user_id );
   }
}
