my $local_users_preparer = local_users_preparer( 2 );

my $remote_user_preparer = remote_user_preparer();

# Ensure all the users are members of a shared room, so that we know presence
# messages can be shared between them all
my $room_preparer = room_preparer(
   requires_users => [ $local_users_preparer, $remote_user_preparer ],
);

my $status_msg = "Update for room members";

test "Presence changes are reported to local room members",
   requires => [ $local_users_preparer, $room_preparer,
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
               return unless $event->{type} eq "m.presence";

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
   requires => [ $local_users_preparer, $remote_user_preparer, $room_preparer,
                 qw( can_set_presence can_join_remote_room_by_alias )],

   do => sub {
      my ( $senduser, undef, $remote_user, undef ) = @_;

      await_event_for( $remote_user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.presence";

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
   requires => [ $local_users_preparer, $room_preparer,
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
               return unless $event->{type} eq "m.presence";

               my $content = $event->{content};
               return unless $content->{user_id} eq $senduser->user_id;

               return unless $content->{presence} eq "offline";

               return 1;
            })
         } $senduser, $local_user );
      });
   };

test "Presence changes to OFFLINE are reported to remote room members",
   requires => [ $local_users_preparer, $remote_user_preparer, $room_preparer,
                 qw( can_set_presence can_join_remote_room_by_alias )],

   do => sub {
      my ( $senduser, undef, $remote_user ) = @_;

      await_event_for( $remote_user, sub {
         my ( $event ) = @_;

         return unless $event->{type} eq "m.presence";

         my $content = $event->{content};
         return unless $content->{user_id} eq $senduser->user_id;

         return unless $content->{presence} eq "offline";

         return 1;
      });
   };
