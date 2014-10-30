prepare "Flushing event streams",
   requires => [qw( flush_events_for user more_users )],
   do => sub {
      my ( $flush_events_for, $user, $more_users ) = @_;
      my @users = ( $user, @$more_users );

      Future->needs_all( map { $flush_events_for->( $_ ) } @users );
   };

my $status_msg = "Update for room members";

test "Presence changes are reported to all room members",
   requires => [qw( do_request_json GET_new_events_for user more_users
                    can_set_presence )],

   do => sub {
      my ( $do_request_json, undef, $user, undef ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/presence/:user_id/status",

         content => { presence => "online", status_msg => $status_msg },
      )
   },

   check => sub {
      my ( undef, $GET_new_events_for, $user, $more_users ) = @_;
      my @users = ( $user, @$more_users );

      Future->needs_all( map {
         my $recvuser = $_;

         $GET_new_events_for->( $recvuser, "m.presence",
            timeout => 50,
         )->then( sub {
            my $found;
            foreach my $event ( @_ ) {
               json_keys_ok( $event, qw( type content ));
               json_keys_ok( my $content = $event->{content}, qw( user_id presence status_msg ));

               $content->{user_id} eq $user->user_id or next;

               $found++;

               $content->{status_msg} eq $status_msg or
                  die "Expected content status_msg to '$status_msg'";
            }

            $found or
               die "Failed to find expected m.presence event for ${\$user->user_id}";

            Future->done(1);
         });
      } @users );
   };
