test "Forgotten room messages cannot be paginated",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $user ) = @_;

      matrix_join_room( $user, $room_id )
      ->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "sup" )
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => 1,
               dir   => 'b'
            },
      )})->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( chunk ) );
         log_if_fail "Chunk", $body->{chunk};
         $body->{chunk}[0]{content}{body} eq "sup" or die "Wrong message";

         Future->done(1);
      })->then( sub {
         matrix_leave_room( $user, $room_id )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type => "m.room.member",
            state_key => $user->user_id
         )
      })->then( sub {
         my ( $event ) = @_;

         log_if_fail "member event", $event;
         $event->{membership} eq "leave" or die "Wrong membership state";

         matrix_forget_room( $user, $room_id )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type => "m.room.member",
            state_key => $user->user_id
         )
      })->then( sub {
         my ( $event ) = @_;

         log_if_fail "member event", $event;
         $event->{membership} eq "leave" or die "Wrong membership state";

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => 1,
               dir   => 'b'
            },
      )})->main::expect_http_403;
   };

test "Forgetting room leaves room",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $user ) = @_;

      matrix_join_room( $user, $room_id )
      ->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "sup" )
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => 1,
               dir   => 'b'
            },
      )})->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( chunk ) );
         log_if_fail "Chunk", $body->{chunk};
         $body->{chunk}[0]{content}{body} eq "sup" or die "Wrong message";

         Future->done(1);
      })->then( sub {
         matrix_forget_room( $user, $room_id )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type => "m.room.member",
            state_key => $user->user_id
         )
      })->then( sub {
         my ( $event ) = @_;

         $event->{membership} eq "leave" or die "Wrong membership state";

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => 1,
               dir   => 'b'
            },
      )})->main::expect_http_403;
   };

test "Can re-join room if re-invited - history_visibility = shared",
   requires => [ local_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $creator, $user ) = @_;

      my ( $room_id );

      matrix_create_room( $creator, invite => [ $user->user_id ] )->then( sub {
         ( $room_id ) = @_;

         log_if_fail "room_id", $room_id;

         matrix_put_room_state( $creator, $room_id,
            type => "m.room.join_rules",
            state_key => "",
            content => {
               join_rule => "invite",
            }
         )
      })->then( sub {
         matrix_join_room( $user, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "before leave" );
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => 100,
               dir   => 'b'
            },
         );
      })->then( sub {
         matrix_forget_room( $user, $room_id );
      })->then( sub {
         matrix_join_room( $user, $room_id );
      })->followed_by(\&main::expect_http_403)->then( sub {
         matrix_invite_user_to_room( $creator, $user, $room_id );
      })->then( sub {
         matrix_join_room( $user, $room_id );
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => 100,
               dir   => 'b'
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         my $seen = 0;

         foreach my $event (@{ $body->{chunk} }) {
            $seen = 1 if $event->{type} eq "m.room.message" && $event->{content}->{body} eq "before leave";
         }

         die "Should have seen before leave message" unless $seen;

         matrix_send_room_text_message( $creator, $room_id, body => "after rejoin" );
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => 1,
               dir   => 'b'
            },
      )})->then( sub {
         my ( $body ) = @_;

         log_if_fail "body", $body;

         @{ $body->{chunk} } == 1 or die "Expected event";
         $body->{chunk}[0]->{type} eq "m.room.message" && $body->{chunk}[0]->{content}{body} eq "after rejoin"
            or die "Got wrong event";

         Future->done( 1 );
      });
   };

test "Can re-join room if re-invited - history_visibility joined",
   requires => [ local_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $creator, $user ) = @_;

      my ( $room_id );

      matrix_create_room( $creator, invite => [ $user->user_id ] )->then( sub {
         ( $room_id ) = @_;

         log_if_fail "room_id", $room_id;

         matrix_put_room_state( $creator, $room_id,
            type => "m.room.join_rules",
            state_key => "",
            content => {
               join_rule => "invite",
            }
         )
      })->then( sub {
         matrix_set_room_history_visibility( $creator, $room_id, "joined");
      })->then( sub {
         matrix_join_room( $user, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "before leave" );
      })->then( sub {
         matrix_forget_room( $user, $room_id );
      })->then( sub {
         matrix_join_room( $user, $room_id );
      })->main::expect_http_403->then( sub {
         matrix_invite_user_to_room( $creator, $user, $room_id );
      })->then( sub {
         matrix_join_room( $user, $room_id );
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => 100,
               dir   => 'b'
            },
         );
      })->then( sub {
         my ( $body ) = @_;

         foreach my $event (@{ $body->{chunk} }) {
            die "Should not have seen any m.room.message events" if $event->{type} eq "m.room.message";
         }

         matrix_send_room_text_message( $creator, $room_id, body => "after rejoin" );
      })->then( sub {
         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/messages",
            params => {
               limit => 1,
               dir   => 'b'
            },
      )})->then( sub {
         my ( $body ) = @_;

         log_if_fail "body", $body;

         @{ $body->{chunk} } == 1 or die "Expected event";
         $body->{chunk}[0]->{type} eq "m.room.message" && $body->{chunk}[0]->{content}{body} eq "after rejoin"
            or die "Got wrong event";

         Future->done( 1 );
      });
   };

push our @EXPORT, qw( matrix_forget_room );

sub matrix_forget_room
{
   my ( $user, $room_id ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   do_request_json_for( $user,
      method => "POST",
      uri    => "/api/v1/rooms/$room_id/forget",

      content => {},
   )->then_done(1);
}
