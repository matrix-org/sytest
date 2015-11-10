my $senduser_fixture = local_user_fixture();

my $local_user_fixture = local_user_fixture();

my $remote_user_fixture = remote_user_fixture();

# Ensure all the users are members of a shared room, so that we know presence
# messages can be shared between them all
my $room_fixture = room_fixture(
   requires_users => [
      $senduser_fixture, $local_user_fixture, $remote_user_fixture
   ],
);

my $status_msg = "Update for room members";

test "Presence changes are reported to local room members",
   requires => [ $senduser_fixture, $local_user_fixture, $room_fixture,
                 qw( can_set_presence )],

   do => sub {
      my ( $senduser, $local_user, undef ) = @_;

      do_request_json_for( $senduser,
         method => "PUT",
         uri    => "/api/v1/presence/:user_id/status",

         content => { presence => "online", status_msg => $status_msg },
      )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_event_for( $recvuser, sub {
               my ( $event ) = @_;

               $event->{type} eq "m.presence" or
                  return 0;

               require_json_keys( $event, qw( type content ));
               require_json_keys( my $content = $event->{content},
                  qw( user_id presence ));

               $content->{user_id} eq $senduser->user_id or return;

               # Disabled for now; see SYT-34
               # require_json_keys( $content, qw( status_msg ));
               #
               # $content->{status_msg} eq $status_msg or
               #    die "Expected content status_msg to '$status_msg'";

               return 1;
            });
         } $senduser, $local_user );
      });
   };

test "Presence changes are also reported to remote room members",
   requires => [ $senduser_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_set_presence can_join_remote_room_by_alias )],

   do => sub {
      my ( $senduser, $remote_user, undef ) = @_;

      await_event_for( $remote_user, sub {
         my ( $event ) = @_;

         $event->{type} eq "m.presence" or
            return 0;

         require_json_keys( $event, qw( type content ));
         require_json_keys( my $content = $event->{content},
            qw( user_id presence ));

         # The next presence message we get might not necessarily be the
         # one we were expecting, given this is remote. Wait to get the
         # right one
         $content->{user_id} eq $senduser->user_id or return;

         $content->{status_msg} and $content->{status_msg} eq $status_msg
            or return;

         return 1;
      });
   };

test "Presence changes to OFFLINE are reported to local room members",
   requires => [ $senduser_fixture, $local_user_fixture, $room_fixture,
                 qw( can_set_presence )],

   do => sub {
      my ( $senduser, $local_user, undef ) = @_;

      do_request_json_for( $senduser,
         method => "PUT",
         uri    => "/api/v1/presence/:user_id/status",

         content => { presence => "offline" },
      )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_event_for( $recvuser, sub {
               my ( $event ) = @_;

               $event->{type} eq "m.presence" or
                  return 0;

               my $content = $event->{content};
               $content->{user_id} eq $senduser->user_id or
                  return 0;

               $content->{presence} eq "offline" or
                  return 0;

               return 1;
            })
         } $senduser, $local_user );
      });
   };

test "Presence changes to OFFLINE are reported to remote room members",
   requires => [ $senduser_fixture, $remote_user_fixture, $room_fixture,
                 qw( can_set_presence can_join_remote_room_by_alias )],

   do => sub {
      my ( $senduser, $remote_user, undef ) = @_;

      await_event_for( $remote_user, sub {
         my ( $event ) = @_;

         $event->{type} eq "m.presence" or
            return 0;

         my $content = $event->{content};
         $content->{user_id} eq $senduser->user_id or
            return 0;

         $content->{presence} eq "offline" or
            return 0;

         return 1;
      });
   };

test "Newly created users see their own presence in /initialSync (SYT-34)",
   requires => [ local_user_fixture(),
                 qw( can_initial_sync )],

   do => sub {
      my ( $user ) = @_;

      matrix_initialsync( $user )->then( sub {
         my ( $body ) = @_;

         log_if_fail "initialSync response", $body;

         require_json_keys( $body, qw( presence ));
         require_json_list( my $presence = $body->{presence} );

         my $user_presence = first {
            $_->{content}{user_id} eq $user->user_id
         } @$presence or die "Expected to find my own presence";

         # Doesn't necessarily have a status_msg yet
         require_json_keys( $user_presence, qw( type content ));
         require_json_keys( $user_presence->{content},
            qw( presence last_active_ago ));

         Future->done(1);
      });
   };
