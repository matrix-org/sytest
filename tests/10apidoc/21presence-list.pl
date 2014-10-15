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

         Future->done(1);
      });
   };
