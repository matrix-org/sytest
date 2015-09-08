# Eventually this will be changed; see SPEC-53
my $PRESENCE_LIST_URI = "/api/v1/presence/list/:user_id";

prepare "Flushing event stream",
   requires => [qw( flush_events_for user )],
   do => sub {
      my ( $flush_events_for, $user ) = @_;
      $flush_events_for->( $user );
   };

test "initialSync sees my presence status",
   requires => [qw( do_request_json user can_initial_sync )],

   check => sub {
      my ( $do_request_json, $user ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/api/v1/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( presence ));

         my $found;

         foreach my $event ( @{ $body->{presence} } ) {
            require_json_object( $event, qw( type content ));
            $event->{type} eq "m.presence" or
               die "Expected type of event to be m.presence";

            my $content = $event->{content};
            require_json_object( $content, qw( user_id presence last_active_ago ));

            next unless $content->{user_id} eq $user->user_id;

            $found = 1;
         }

         $found or
            die "Did not find an initial presence message about myself";

         Future->done(1);
      });
   };

my $status_msg = "A status set by 21presence-events.pl";

test "Presence change reports an event to myself",
   requires => [qw( do_request_json await_event_for user can_set_presence )],

   do => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/api/v1/presence/:user_id/status",

         content => { presence => "online", status_msg => $status_msg },
      )
   },

   await => sub {
      my ( undef, $await_event_for, $user ) = @_;

      $await_event_for->( $user, sub {
         my ( $event ) = @_;
         next unless $event->{type} eq "m.presence";
         my $content = $event->{content};
         next unless $content->{user_id} eq $user->user_id;

         $content->{status_msg} eq $status_msg or
            die "Expected status_msg to be '$status_msg'";

         return 1;
      });
   };

my $friend_status = "Status of a Friend";

test "Friends presence changes reports events",
   requires => [qw( do_request_json_for await_event_for user more_users
                    can_set_presence can_invite_presence )],

   do => sub {
      my ( $do_request_json_for, undef, $user, $more_users ) = @_;
      my $friend = $more_users->[0];

      $do_request_json_for->( $user,
         method => "POST",
         uri    => $PRESENCE_LIST_URI,

         content => {
            invite => [ $friend->user_id ],
         }
      )->then( sub {
         $do_request_json_for->( $friend,
            method => "PUT",
            uri    => "/api/v1/presence/:user_id/status",

            content => { presence => "online", status_msg => $friend_status },
         );
      });
   },

   await => sub {
      my ( undef, $await_event_for, $user, $more_users ) = @_;
      my $friend = $more_users->[0];

      $await_event_for->( $user, sub {
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
   };

prepare "Clearing presence list",
   requires => [qw( do_request_json can_invite_presence can_drop_presence )],

   do => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => $PRESENCE_LIST_URI,
      )->then( sub {
         my ( $body ) = @_;

         my @ids = map { $_->{user_id} } @$body;

         $do_request_json->(
            method => "POST",
            uri    => $PRESENCE_LIST_URI,

            content => { drop => \@ids },
         );
      });
   };
