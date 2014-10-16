my $status_msg = "Another status message";

test "GET /events sees my presence change",
   requires => [qw( do_request_json_authed GET_events_after user_id
                    can_set_presence )],

   do => sub {
      my ( $do_request_json_authed, $GET_events_after, $user_id ) = @_;

      $GET_events_after->( sub {
         $do_request_json_authed->(
            method => "PUT",
            uri    => "/presence/:user_id/status",

            content => {
               presence   => "online",
               status_msg => $status_msg,
            },
         )
      })->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( type content ));
            next unless $event->{type} eq "m.presence";

            my $content = $event->{content};
            json_keys_ok( $content, qw( user_id ));

            next unless $content->{user_id} eq $user_id;

            $found = 1;

            json_keys_ok( $content, qw( presence status_msg ));
            $content->{presence} eq "online" or
               die "Expected presence to be 'online'\n";
            $content->{status_msg} eq $status_msg or
               die "Expected status_msg to be '$status_msg'\n";
         }

         $found or
            die "Did not find an appropriate presence event\n";

         Future->done(1);
      });
   };

my $friend_status = "Status of a Friend";

test "GET /events sees friend presence change",
   requires => [qw( first_http_client more_users GET_events_after user_id
                    can_set_presence can_invite_presence )],

   do => sub {
      my ( $http, $more_users, $GET_events_after, $user_id ) = @_;
      my $friend = $more_users->[0];

      $GET_events_after->( sub {
         $http->do_request_json(
            method => "PUT",
            uri    => "/presence/${\$friend->user_id}/status",
            params => { access_token => $friend->access_token },

            content => {
               presence   => "online",
               status_msg => $friend_status,
            },
         )
      })->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            json_keys_ok( $event, qw( type content ));
            next unless $event->{type} eq "m.presence";

            my $content = $event->{content};
            json_keys_ok( $content, qw( user_id ));

            next unless $content->{user_id} eq $friend->user_id;

            $found = 1;

            json_keys_ok( $content, qw( presence status_msg ));
            $content->{presence} eq "online" or
               die "Expected presence to be 'online'\n";
            $content->{status_msg} eq $friend_status or
               die "Expected status_msg to be '$friend_status'\n";
         }

         $found or
            die "Did not find an appropriate presence event\n";

         Future->done(1);
      });
   };

test "GET /initialSync sees status",
   requires => [qw( do_request_json_authed user_id can_initial_sync )],

   check => sub {
      my ( $do_request_json_authed, $user_id ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( presence ));

         my $found;

         foreach my $event ( @{ $body->{presence} } ) {
            json_object_ok( $event, qw( type content ));
            $event->{type} eq "m.presence" or
               die "Expected type of event to be m.presence";

            my $content = $event->{content};
            json_object_ok( $content, qw( user_id presence last_active_ago ));

            next unless $content->{user_id} eq $user_id;

            $found = 1;
         }

         $found or
            die "Did not find an initial presence message about myself";

         Future->done(1);
      });
   };
