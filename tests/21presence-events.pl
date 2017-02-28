# Eventually this will be changed; see SPEC-53
my $PRESENCE_LIST_URI = "/r0/presence/list/:user_id";


test "initialSync sees my presence status",
   requires => [ local_user_fixture(),
                 qw( can_initial_sync )],

   check => sub {
      my ( $user ) = @_;

      # We add a filler account data entry to ensure that replication is up to
      # date with account creation. Really this should be a synced presence
      # set
      matrix_add_filler_account_data_synced ( $user )->then( sub {
         matrix_initialsync( $user )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( presence ));

         log_if_fail "Initial sync presence", $body->{presence};

         my $event = first {
            ( $_->{content}{user_id} // "" ) eq $user->user_id
         } @{ $body->{presence} } or
            die "Did not find an initial presence message about myself";

         assert_json_object( $event, qw( type content ));
         $event->{type} eq "m.presence" or
            die "Expected type of event to be m.presence";

         my $content = $event->{content};
         assert_json_object( $content, qw( user_id presence last_active_ago ));

         Future->done(1);
      });
   };

my $status_msg = "A status set by 21presence-events.pl";

test "Presence change reports an event to myself",
   requires => [ local_user_fixture(),
                 qw( can_set_presence )],

   do => sub {
      my ( $user ) = @_;

      matrix_set_presence_status( $user, "online",
         status_msg => $status_msg,
      )->then( sub {
         await_event_for( $user, filter => sub {
            my ( $event ) = @_;
            return 0 unless $event->{type} eq "m.presence";
            my $content = $event->{content};
            return 0 unless $content->{user_id} eq $user->user_id;

            return 0 unless ( $content->{status_msg} // "" ) eq $status_msg;

            return 1;
         });
      });
   };

my $friend_status = "Status of a Friend";

test "Friends presence changes reports events",
   requires => [ local_user_fixture(), local_user_fixture(),
                 qw( can_set_presence can_invite_presence )],

   do => sub {
      my ( $user, $friend ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => $PRESENCE_LIST_URI,

         content => {
            invite => [ $friend->user_id ],
         }
      )->then( sub {
         flush_events_for( $user )
      })->then( sub {
         matrix_set_presence_status( $friend, "online",
            status_msg => $friend_status,
         );
      })->then( sub {
         await_event_for( $user, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";

            my $content = $event->{content};
            assert_json_keys( $content, qw( user_id ));

            return unless $content->{user_id} eq $friend->user_id;

            assert_json_keys( $content, qw( presence status_msg ));
            $content->{presence} eq "online" or
               die "Expected presence to be 'online'";
            $content->{status_msg} eq $friend_status or
               die "Expected status_msg to be '$friend_status'";

            return 1;
         });
      });
   };
