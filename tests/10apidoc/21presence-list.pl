# Eventually this will be changed; see SPEC-53
my $PRESENCE_LIST_URI = "/presence/list/:user_id";

test "GET /presence/:user_id/list initially empty",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => $PRESENCE_LIST_URI,
      )->then( sub {
         my ( $body ) = @_;

         json_list_ok( $body );
         @$body == 0 or die "Expected an empty list";

         Future->done(1);
      });
   };

test "POST /presence/:user_id/list can invite users",
   requires => [qw( do_request_json_authed more_users )],

   do => sub {
      my ( $do_request_json_authed, $more_users ) = @_;
      my $friend_uid = $more_users->[0]->user_id;

      $do_request_json_authed->(
         method => "POST",
         uri    => $PRESENCE_LIST_URI,

         content => {
            invite => [ $friend_uid ],
         },
      );
   },

   check => sub {
      my ( $do_request_json_authed, $more_users ) = @_;
      my $friend_uid = $more_users->[0]->user_id;

      $do_request_json_authed->(
         method => "GET",
         uri    => $PRESENCE_LIST_URI,
      )->then( sub {
         my ( $body ) = @_;

         json_list_ok( $body );
         scalar @$body > 0 or die "Expected non-empty list\n";

         json_keys_ok( $body->[0], qw( accepted presence user_id ));
         $body->[0]->{user_id} eq $friend_uid or die "Expected friend user_id\n";

         provide can_invite_presence => 1;

         Future->done(1);
      });
   };

my $friend_status = "Status of a Friend";

test "GET /events sees friend presence change",
   requires => [qw( first_http_client more_users GET_new_events
                    can_set_presence can_invite_presence )],

   do => sub {
      my ( $http, $more_users, $GET_new_events ) = @_;
      my $friend = $more_users->[0];

      $http->do_request_json(
         method => "PUT",
         uri    => "/presence/${\$friend->user_id}/status",
         params => { access_token => $friend->access_token },

         content => {
            presence   => "online",
            status_msg => $friend_status,
         },
      )->then( sub {
         $GET_new_events->( "m.presence" )
      })->then( sub {
         my $found;

         foreach my $event ( @_ ) {
            my $content = $event->{content};
            json_keys_ok( $content, qw( user_id ));

            next unless $content->{user_id} eq $friend->user_id;
            $found++;

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
