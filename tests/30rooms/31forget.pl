use List::Util qw( any none );

test "Forgotten room messages cannot be paginated",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $user ) = @_;

      matrix_join_room( $user, $room_id )
      ->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "sup" )
      })->then( sub {
         matrix_get_room_messages( $user, $room_id, limit => 1 );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );
         log_if_fail "Chunk", $body->{chunk};
         $body->{chunk}[0]{content}{body} eq "sup" or die "Wrong message";

         matrix_leave_room( $user, $room_id )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.member",
            state_key => $user->user_id
         )
      })->then( sub {
         my ( $content ) = @_;

         assert_eq( $content->{membership}, "leave",
            "membership state" );

         matrix_forget_room( $user, $room_id )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.member",
            state_key => $user->user_id
         )
      })->then( sub {
         my ( $content ) = @_;

         assert_eq( $content->{membership}, "leave",
            "membership state" );

         matrix_get_room_messages( $user, $room_id, limit => 1 )
            ->main::expect_http_403;
      });
   };

test "Forgetting room does not show up in v2 /sync",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $user ) = @_;

      matrix_join_room( $user, $room_id )
      ->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "sup" )
      })->then( sub {
         matrix_leave_room( $user, $room_id )
      })->then( sub {
         matrix_forget_room( $user, $room_id )
      })->then( sub {
         matrix_sync( $user )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Sync response", $body;

         die "Did not expect room in archived" if $body->{rooms}->{archived}->{$room_id};
         die "Did not expect room in joined" if $body->{rooms}->{joined}->{$room_id};
         die "Did not expect room in invited" if $body->{rooms}->{invited}->{$room_id};

         Future->done( 1 );
      });
   };

test "Can forget room you've been kicked from",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $user ) = @_;

      matrix_join_room( $user, $room_id )
      ->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "sup" );
      })->then( sub {
         do_request_json_for( $creator,
            method => "POST",
            uri    => "/r0/rooms/$room_id/kick",

            content => { user_id => $user->user_id },
         );
      })->then( sub {
         matrix_forget_room( $user, $room_id )
      })->then( sub {
         matrix_sync( $user )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Sync response", $body;

         die "Did not expect room in archived" if $body->{rooms}->{archived}->{$room_id};
         die "Did not expect room in joined" if $body->{rooms}->{joined}->{$room_id};
         die "Did not expect room in invited" if $body->{rooms}->{invited}->{$room_id};

         Future->done( 1 );
      });
   };


test "Can't forget room you're still in",
   requires => [ local_user_and_room_fixtures(), local_user_fixture() ],

   do => sub {
      my ( $creator, $room_id, $user ) = @_;

      matrix_join_room( $user, $room_id )
      ->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "sup" );
      })->then( sub {
         matrix_forget_room( $user, $room_id )
      })->main::expect_http_4xx;
   };

test "Can re-join room if re-invited",
   requires => [ local_user_fixture(), local_user_fixture() ],

   do => sub {
      my ( $creator, $user ) = @_;

      my ( $room_id );

      matrix_create_room( $creator, invite => [ $user->user_id ] )->then( sub {
         ( $room_id ) = @_;

         log_if_fail "room_id", $room_id;

         matrix_put_room_state( $creator, $room_id,
            type      => "m.room.join_rules",
            state_key => "",
            content   => {
               join_rule => "invite",
            }
         )
      })->then( sub {
         matrix_join_room( $user, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $creator, $room_id, body => "before leave" );
      })->then( sub {
         matrix_get_room_messages( $user, $room_id, limit => 100 );
      })->then( sub {
         matrix_leave_room( $user, $room_id );
      })->then( sub {
         matrix_forget_room( $user, $room_id );
      })->then( sub {
         matrix_join_room( $user, $room_id )->main::expect_http_403;
      })->then( sub {
         matrix_invite_user_to_room( $creator, $user, $room_id );
      })->then( sub {
         matrix_join_room( $user, $room_id );
      })->then( sub {
         matrix_get_room_messages( $user, $room_id, limit => 100 );
      })->then( sub {
         my ( $body ) = @_;

         any { $_->{type} eq "m.room.message" && $_->{content}->{body} eq "before leave" } @{ $body->{chunk} }
            or die "Should have seen before leave message";

         matrix_send_room_text_message( $creator, $room_id, body => "after rejoin" );
      })->then( sub {
         matrix_get_room_messages( $user, $room_id, limit => 1 );
      })->then( sub {
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
      uri    => "/r0/rooms/$room_id/forget",

      content => {},
   )->then_done(1);
}
