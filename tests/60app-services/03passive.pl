my $user_fixture = local_user_fixture( with_event => 1);

my $room_fixture = room_fixture( $user_fixture );

test "Inviting an AS-hosted user asks the AS server",
   requires => [ $main::AS_USER[0], $main::APPSERV[0], $user_fixture, $room_fixture,
                 qw( can_invite_room )],

   do => sub {
      my ( $as_user, $appserv, $creator, $room_id ) = @_;
      my $server_name = $as_user->http->server_name;

      my $localpart = "astest-03passive-1";
      my $user_id = "\@$localpart:$server_name";

      require_stub $appserv->await_http_request( "/users/$user_id", sub { 1 } )
         ->then( sub {
            my ( $request ) = @_;

            matrix_register_as_ghost( $as_user, $localpart )->on_done( sub {
               $request->respond_json( {} );
            });
         });

      Future->needs_all(
         $appserv->await_event( "m.room.member" )
         ->then( sub {
            my ( $event ) = @_;

            log_if_fail "Event", $event;

            assert_json_keys( $event, qw( content room_id user_id ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";
            $event->{state_key} eq $user_id or
               die "Expected user_id to be $user_id";

            Future->done;
         }),

         matrix_invite_user_to_room( $creator, $user_id, $room_id ),
      );
   };

multi_test "Accesing an AS-hosted room alias asks the AS server",
   requires => [ $main::AS_USER[0], $main::APPSERV[0], local_user_fixture(), $room_fixture,
                 room_alias_fixture( prefix => "astest-" ),

                qw( can_join_room_by_alias )],

   do => sub {
      my ( $as_user, $appserv, $local_user, $room_id, $room_alias ) = @_;

      require_stub $appserv->await_http_request( "/rooms/$room_alias", sub { 1 } )
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
         $appserv->await_event( "m.room.member" )->then( sub {
            my ( $event ) = @_;

            log_if_fail "Event", $event;

            assert_json_keys( $event, qw( content room_id user_id state_key ));

            assert_eq($event->{room_id}, $room_id, "Event room_id");
            assert_eq($event->{user_id}, $local_user->user_id, "Event user_id");
            assert_eq($event->{state_key}, $local_user->user_id, "Event state_key");

            assert_json_keys( $event->{content}, qw( membership ));
            assert_eq($event->{content}{membership}, "join", "Event membership");

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
   requires => [ $user_fixture, $room_fixture, $main::APPSERV[0],
                 qw( can_join_room_by_alias can_send_message )],

   do => sub {
      my ( $creator, $room_id, $appserv ) = @_;

      Future->needs_all(
         $appserv->await_event( "m.room.message" )->then( sub {
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
