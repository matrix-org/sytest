use Future::Utils qw( repeat );

test "The only membership state included in an initial sync are for all the senders in the timeline",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $alice, $bob, $charlie ) = @_;

      # Alice creates a public room,
      # Bob sends 10 events into it
      # Charlie sends 10 events into it
      # Alice syncs with a filter on the last 10 events, and lazy loaded members
      # She should only see Charlie in the membership list.

      my ( $filter_id, $room_id, $event_id_1, $event_id_2 );

      matrix_create_filter( $alice, {
         room => {
            state => {
               lazy_load_members => JSON::true
            },
            timeline => {
               limit => 10
            },
         }
      } )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room_synced( $alice );
      })->then( sub {
         ( $room_id ) = @_;
         matrix_join_room( $bob, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $bob, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         matrix_join_room( $charlie, $room_id );
      })->then( sub {
         repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message( $charlie, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         matrix_sync( $alice, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         my $timeline = $room->{timeline}{events};

         log_if_fail "Room", $room;

         assert_json_keys( $room, qw( timeline state ephemeral ));

         my @members = grep { $_->{type} eq 'm.room.member' } @{ $room->{state}{events} };
         @members == 1
            or die "Expected only one membership event";

         my $event = $members[0];

         $event->{type} eq "m.room.member"
            or die "Unexpected state event type";

         assert_json_keys( $event, qw( sender state_key content ));
         $event->{sender} eq $charlie->user_id
            or die "Unexpected sender";
         $event->{state_key} eq $charlie->user_id
            or die "Unexpected state_key";

         assert_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "join" or
            die "Expected membership as 'join'";

         Future->done(1);
      });
   };

#test "The only membership state included in an incremental sync are for senders in the timeline"

#test "The only membership state included in a gapped incremental sync are for senders in the timeline"

#test "We don't send redundant membership state across incremental syncs"
