my $user_fixture = local_user_fixture( with_events => 1 );

multi_test "AS-ghosted users can use rooms via AS",
   requires => [ as_ghost_fixture(), $main::AS_USER[0], $user_fixture, $main::APPSERV[0],
                     room_fixture( $user_fixture ),
                qw( can_receive_room_message_locally )],

   do => sub {
      my ( $ghost, $as_user, $creator, $appserv, $room_id ) = @_;

      Future->needs_all(
         $appserv->await_event( "m.room.member" )->then( sub {
            my ( $event ) = @_;

            log_if_fail "AS event", $event;

            assert_json_keys( $event, qw( content room_id ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";
            $event->{state_key} eq $ghost->user_id or
               die "Expected state_key to be ${\$ghost->user_id}";

            assert_json_keys( my $content = $event->{content}, qw( membership ) );

            $content->{membership} eq "join" or
               die "Expected membership to be 'join'";

            Future->done;
         }),

         do_request_json_for( $as_user,
            method => "POST",
            uri    => "/r0/rooms/$room_id/join",
            params => {
               user_id => $ghost->user_id,
            },

            content => {},
         )
      )->SyTest::pass_on_done( "User joined room via AS" )
      ->then( sub {
         Future->needs_all(
            $appserv->await_event( "m.room.message" )->then( sub {
               my ( $event ) = @_;

               log_if_fail "AS event", $event;

               assert_json_keys( $event, qw( room_id user_id ));

               $event->{room_id} eq $room_id or
                  die "Expected room_id to be $room_id";
               $event->{user_id} eq $ghost->user_id or
                  die "Expected sender user_id to be ${\$ghost->user_id}";

               Future->done;
            }),

            do_request_json_for( $as_user,
               method => "POST",
               uri    => "/r0/rooms/$room_id/send/m.room.message",
               params => {
                  user_id => $ghost->user_id,
               },

               content => { msgtype => "m.text", body => "Message from AS directly" },
            )
         )
      })->SyTest::pass_on_done( "User posted message via AS" )
      ->then( sub {
         await_event_for( $creator, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{room_id} eq $room_id;

            log_if_fail "Event", $event;

            my $content = $event->{content};

            $content->{body} eq "Message from AS directly" or
               die "Expected 'body' as 'Message from AS directly'";
            $event->{user_id} eq $ghost->user_id or
               die "Expected sender user_id as ${\$ghost->user_id}";

            return 1;
         })->on_done( sub { "Creator received user's message" } )
      })->then_done(1);
   };

multi_test "AS-ghosted users can use rooms themselves",
   requires => [ as_ghost_fixture(), $user_fixture, $main::APPSERV[0],
                     room_fixture( $user_fixture ),
                qw( can_receive_room_message_locally can_send_message )],

   do => sub {
      my ( $ghost, $creator, $appserv, $room_id ) = @_;

      Future->needs_all(
         $appserv->await_event( "m.room.member" )->then( sub {
            my ( $event ) = @_;

            log_if_fail "AS event", $event;

            assert_json_keys( $event, qw( content room_id ));

            $event->{room_id} eq $room_id or
               die "Expected room_id to be $room_id";

            assert_json_keys( my $content = $event->{content}, qw( membership ) );

            $content->{membership} eq "join" or
               die "Expected membership to be 'join'";

            Future->done;
         }),

         matrix_join_room( $ghost, $room_id )
      )->SyTest::pass_on_done( "Ghost joined room themselves" )
      ->then( sub {
         Future->needs_all(
            $appserv->await_event( "m.room.message" )->then( sub {
               my ( $event ) = @_;

               log_if_fail "AS event", $event;

               assert_json_keys( $event, qw( room_id user_id ));

               $event->{room_id} eq $room_id or
                  die "Expected room_id to be $room_id";
               $event->{user_id} eq $ghost->user_id or
                  die "Expected sender user_id to be ${\$ghost->user_id}";

               Future->done;
            }),

            matrix_send_room_text_message( $ghost, $room_id,
               body => "Message from AS Ghost",
            )
         )
      })->SyTest::pass_on_done( "Ghost posted message themselves" )
      ->then( sub {
         await_event_for( $creator, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.room.message";
            return unless $event->{room_id} eq $room_id;

            log_if_fail "Event", $event;

            my $content = $event->{content};

            $content->{body} eq "Message from AS Ghost" or
               die "Expected 'body' as 'Message from AS Ghost'";
            $event->{user_id} eq $ghost->user_id or
               die "Expected sender user_id as ${\$ghost->user_id}";

            return 1;
         })->SyTest::pass_on_done( "Creator received ghost's message" )
      })->then_done(1);
   };

my $unregistered_as_user_localpart = "astest-02ghost-1";

test "Ghost user must register before joining room",
   requires => [ $main::AS_USER[0], local_user_and_room_fixtures(), $main::HOMESERVER_INFO[0] ],

   check => sub {
      my ( $as_user, undef, $room_id, $hs_info ) = @_;

      do_request_json_for( $as_user,
         method => "POST",
         uri    => "/r0/rooms/$room_id/join",
         params => {
            user_id => "@".$unregistered_as_user_localpart.":".$hs_info->server_name,
         },
         content => {},
      );
   },

   do => sub {
      my ( $as_user, undef, $room_id ) = @_;

      do_request_json_for( $as_user,
         method => "POST",
         uri    => "/r0/register",

         content => {
            user => $unregistered_as_user_localpart,
         },
      );
   };


my $avatar_url = "http://somewhere/my-pic.jpg";

test "AS can set avatar for ghosted users",
   requires => [ as_ghost_fixture(), $main::AS_USER[0],
                 qw( can_get_avatar_url ) ],

   check => sub {
      my ( $ghost, $as_user ) = @_;

      my $user_id = $ghost->user_id;

      my $http = $as_user->http;

      $http->do_request_json(
         method => "GET",
         uri    => "/r0/profile/$user_id/avatar_url",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( avatar_url ));
         assert_eq( $body->{avatar_url}, $avatar_url, 'avatar_url' );

         Future->done(1);
      });
   },

   do => sub {
      my ( $ghost, $as_user ) = @_;

      my $user_id = $ghost->user_id;

      do_request_json_for(
         $as_user,
         method => "PUT",
         uri    => "/r0/profile/$user_id/avatar_url",
         params => {
            user_id => $user_id,
         },
         content => { avatar_url => $avatar_url },
      );
   };


my $displayname = "Ghost user's new name";

test "AS can set displayname for ghosted users",
   requires => [ as_ghost_fixture(), $main::AS_USER[0],
                 qw( can_get_displayname ) ],

   check => sub {
      my ( $ghost, $as_user ) = @_;

      my $user_id = $ghost->user_id;

      my $http = $as_user->http;

      $http->do_request_json(
         method => "GET",
         uri    => "/r0/profile/$user_id/displayname",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( displayname ));
         assert_eq( $body->{displayname}, $displayname, 'displayname' );

         Future->done(1);
      });
   },

   do => sub {
      my ( $ghost, $as_user ) = @_;
      as_set_displayname_for_user( $as_user, $ghost, $displayname );
   };


test "AS can't set displayname for random users",
   requires => [ $main::AS_USER[0], $user_fixture ],

   do => sub {
      my ( $as_user, $regular_user ) = @_;

      as_set_displayname_for_user(
         $as_user, $regular_user, $displayname
      )->main::expect_http_403;
   };

sub as_set_displayname_for_user {
   my ( $as_user, $target_user, $displayname ) = @_;

   my $user_id = $target_user->user_id;

   do_request_json_for(
      $as_user,
      method => "PUT",
      uri    => "/r0/profile/$user_id/displayname",
      content => { displayname => $displayname },
      params => {
         user_id => $user_id,
      },
   );
}
