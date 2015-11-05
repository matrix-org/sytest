# Eventually this will be changed; see SPEC-53
my $PRESENCE_LIST_URI = "/api/v1/presence/list/:user_id";

my $preparer = local_user_preparer();

test "initialSync sees my presence status",
   requires => [ $preparer,
                 qw( can_initial_sync )],

   check => sub {
      my ( $user ) = @_;

      matrix_initialsync( $user )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( presence ));

         log_if_fail "Initial sync presence", $body->{presence};

         my $event = first {
            ( $_->{content}{user_id} // "" ) eq $user->user_id
         } @{ $body->{presence} } or
            die "Did not find an initial presence message about myself";

         require_json_object( $event, qw( type content ));
         $event->{type} eq "m.presence" or
            die "Expected type of event to be m.presence";

         my $content = $event->{content};
         require_json_object( $content, qw( user_id presence last_active_ago ));

         Future->done(1);
      });
   };

my $status_msg = "A status set by 21presence-events.pl";

test "Presence change reports an event to myself",
   requires => [ $preparer,
                 qw( can_set_presence )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/presence/:user_id/status",

         content => { presence => "online", status_msg => $status_msg },
      )->then( sub {
         await_event_for( $user, sub {
            my ( $event ) = @_;
            next unless $event->{type} eq "m.presence";
            my $content = $event->{content};
            next unless $content->{user_id} eq $user->user_id;

            $content->{status_msg} eq $status_msg or
               die "Expected status_msg to be '$status_msg'";

            return 1;
         });
      });
   };

my $friend_status = "Status of a Friend";

test "Friends presence changes reports events",
   requires => [ $preparer, local_user_preparer(),
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
         do_request_json_for( $friend,
            method => "PUT",
            uri    => "/api/v1/presence/:user_id/status",

            content => { presence => "online", status_msg => $friend_status },
         );
      })->then( sub {
         await_event_for( $user, sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";

            my $content = $event->{content};
            require_json_keys( $content, qw( user_id ));

            return unless $content->{user_id} eq $friend->user_id;

            require_json_keys( $content, qw( presence status_msg ));
            $content->{presence} eq "online" or
               die "Expected presence to be 'online'";
            $content->{status_msg} eq $friend_status or
               die "Expected status_msg to be '$friend_status'";

            return 1;
         });
      });
   };
