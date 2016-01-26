my $user_fixture = local_user_fixture();

my $room_fixture = room_fixture(
   requires_users => [ $user_fixture ],
);

multi_test "Inviting an AS-hosted user asks the AS server",
   requires => [ $main::AS_USER, $user_fixture, $room_fixture,
                 qw( can_invite_room )],

   do => sub {
      my ( $as_user, $creator, $room_id ) = @_;
      my $server_name = $as_user->http->server_name;

      my $localpart = "astest-03passive-1";
      my $user_id = "\@$localpart:$server_name";

      require_stub await_http_request( "/appserv/users/$user_id", sub { 1 } )
         ->then( sub {
            my ( $request ) = @_;

            matrix_register_as_ghost( $as_user, $localpart )->on_done( sub {
               $request->respond_json( {} );
            });
         });

      matrix_invite_user_to_room( $creator, $user_id, $room_id )
         ->SyTest::pass_on_done( "Sent invite" )
      ->then( sub {
         await_as_event( "m.room.member" )
      })->then( sub {
         my ( $event ) = @_;

         log_if_fail "Event", $event;

         assert_json_keys( $event, qw( content room_id user_id ));

         $event->{room_id} eq $room_id or
            die "Expected room_id to be $room_id";
         $event->{state_key} eq $user_id or
            die "Expected user_id to be $user_id";

         Future->done;
      });
   };

multi_test "Accesing an AS-hosted room alias asks the AS server",
   requires => [ $main::AS_USER, local_user_fixture(), $room_fixture,
                 room_alias_fixture( prefix => "astest-" ),

                qw( can_join_room_by_alias )],

   do => sub {
      my ( $as_user, $local_user, $room_id, $room_alias ) = @_;

      require_stub await_http_request( "/appserv/rooms/$room_alias", sub { 1 } )
         ->then( sub {
            my ( $request ) = @_;

            pass "Received AS request";

            do_request_json_for( $as_user,
               method => "PUT",
               uri    => "/r0/directory/room/$room_alias",

               content => {
                  room_id => $room_id,
               },
            )->SyTest::pass_on_done( "Created room alias mapping" )
            ->on_done( sub {
               $request->respond_json( {} );
            });
         });

      Future->needs_all(
         await_as_event( "m.room.member" )->then( sub {
            my ( $event ) = @_;

            log_if_fail "Event", $event;

            assert_json_keys( $event, qw( room_id user_id membership state_key ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";
            $event->{user_id} eq $local_user->user_id or
               die "Expected user_id to be ${\ $local_user->user_id }";
            $event->{membership} eq "join" or
               die "Expected membership to be 'join'";
            $event->{state_key} eq $local_user->user_id or
               die "Expected state_key to be ${\ $local_user->user_id }";

            Future->done;
         }),

         await_as_event( "m.room.aliases" )->then( sub {
            my ( $event ) = @_;

            log_if_fail "Event", $event;

            assert_json_keys( $event, qw( content room_id user_id ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";
            $event->{user_id} eq $as_user->user_id or
               die "Expected user_id to be ${\$as_user->user_id}";

            assert_json_keys( my $content = $event->{content}, qw( aliases ));
            assert_json_list( my $aliases = $content->{aliases} );

            grep { $_ eq $room_alias } @$aliases or
               die "Expected to find our alias in the aliases list";

            Future->done;
         }),

         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/join/$room_alias",

            content => {},
         )
      );
   };

test "Events in rooms with AS-hosted room aliases are sent to AS server",
   requires => [ $user_fixture, $room_fixture,
                 qw( can_join_room_by_alias can_send_message )],

   do => sub {
      my ( $creator, $room_id ) = @_;

      Future->needs_all(
         await_as_event( "m.room.message" )->then( sub {
            my ( $event ) = @_;

            log_if_fail "Event", $event;

            assert_json_keys( $event, qw( content room_id user_id ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";

            Future->done;
         }),

         matrix_send_room_text_message( $creator, $room_id,
            body => "A message for the AS",
         ),
      );
   };
