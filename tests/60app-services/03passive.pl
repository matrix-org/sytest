my $room_id;

prepare "Creating a new test room",
   requires => [qw( make_test_room local_users )],

   do => sub {
      my ( $make_test_room, $local_users ) = @_;
      my $creator   = $local_users->[0];

      $make_test_room->( $creator )
         ->on_done( sub {
            ( $room_id ) = @_;
         });
   };

multi_test "Inviting an AS-hosted user asks the AS server",
   requires => [qw( do_request_json await_http_request await_as_event make_as_user first_home_server
                    can_invite_room )],

   do => sub {
      my ( $do_request_json, $await_http_request, $await_as_event, $make_as_user, $home_server ) = @_;

      my $localpart = "astest-03passive-1";
      my $user_id = "\@$localpart:$home_server";

      Future->needs_all(
         $await_http_request->( "/appserv/users/$user_id", sub { 1 } ) ->then( sub {
            my ( $content, $request ) = @_;

            $make_as_user->( $localpart )->then( sub {
               $request->respond_json( {} );

               Future->done( $request );
            });
         }),

         $do_request_json->(
            method => "POST",
            uri    => "/rooms/$room_id/invite",

            content => { user_id => $user_id },
         ),
      )->then( sub {
         my ( $appserv_request, $invite_response ) = @_;

         pass "Sent invite";

         $await_as_event->( "m.room.member" )->then( sub {
            my ( $event ) = @_;

            log_if_fail "Event", $event;

            require_json_keys( $event, qw( content room_id user_id ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";
            $event->{state_key} eq $user_id or
               die "Expected user_id to be $user_id";

            Future->done;
         });
      });
   };

multi_test "Accesing an AS-hosted room alias asks the AS server",
   requires => [qw( do_request_json_for await_http_request await_as_event as_user local_users first_home_server
                    can_join_room_by_alias )],

   do => sub {
      my ( $do_request_json_for, $await_http_request, $await_as_event, $as_user, $users, $first_home_server ) = @_;
      my $user = $users->[1];
      my $room_alias = "#astest-03passive-1:$first_home_server";

      Future->needs_all(
         $await_http_request->( "/appserv/rooms/$room_alias", sub { 1 } )->then( sub {
            my ( $content, $request ) = @_;

            pass "Received AS request";

            Future->needs_all(
               $await_as_event->( "m.room.aliases" )->then( sub {
                  my ( $event ) = @_;

                  log_if_fail "Event", $event;

                  require_json_keys( $event, qw( content room_id user_id ));

                  $event->{room_id} eq $room_id or
                     die "Expected room_id to be $room_id";
                  $event->{user_id} eq $as_user->user_id or
                     die "Expected user_id to be ${\$as_user->user_id}";

                  require_json_keys( my $content = $event->{content}, qw( aliases ));
                  require_json_list( my $aliases = $content->{aliases} );

                  grep { $_ eq $room_alias } @$aliases or
                     die "Expected to find our alias in the aliases list";

                  Future->done;
               }),

               $do_request_json_for->( $as_user,
                  method => "PUT",
                  uri    => "/directory/room/$room_alias",

                  content => {
                     room_id => $room_id,
                  },
               )->then( sub {
                  pass "Created room alias mapping";

                  $request->respond_json( {} );
                  Future->done;
               }),
            );
         }),

         $do_request_json_for->( $user,
            method => "POST",
            uri    => "/join/$room_alias",

            content => {},
         )
      );
   };
