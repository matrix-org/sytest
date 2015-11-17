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


