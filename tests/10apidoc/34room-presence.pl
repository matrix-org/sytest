my $status_msg = "Update for room members";

test "PUT /presence/:user_id/status updates my presence while in a room",
   requires => [qw( do_request_json flush_events_for user more_users
                    can_set_presence )],

   do => sub {
      my ( $do_request_json, $flush_events_for, $user, $more_users ) = @_;

      # Flush event streams first
      Future->needs_all( map { $flush_events_for->( $_ ) } $user, @$more_users )

      ->then( sub {
         $do_request_json->(
            method => "PUT",
            uri    => "/presence/:user_id/status",

            content => {
               presence => "online",
               status_msg => $status_msg,
            },
         )
      });
   };

test "GET /events by other room members sees presence status change",
   requires => [qw( GET_new_events_for user more_users
                    can_set_presence can_join_room_by_id can_join_room_by_alias )],

   check => sub {
      my ( $GET_new_events_for, $first_user, $more_users ) = @_;

      Future->needs_all( map {
         my $user = $_;

         my $found;

         $GET_new_events_for->( $user, "m.presence" )->then( sub {
            foreach my $event ( @_ ) {
               json_keys_ok( $event, qw( type content ));
               json_keys_ok( $event->{content}, qw( user_id presence status_msg ));

               $event->{content}{user_id} eq $first_user->user_id or next;

               $found++;

               $event->{content}{status_msg} eq $status_msg or
                  die "Expected content status_msg to '$status_msg'";
            }

            $found or
               die "Failed to find expected m.presence event for ${\$user->user_id}";

            Future->done(1);
         });
      } @$more_users );
   };
