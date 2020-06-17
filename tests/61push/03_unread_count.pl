# fixture which registers a user, and sets up a push rule for them
# the push rule matches any content and performs the given action.
#
# returns the user id.
sub user_with_push_rule_fixture
{
   my( $action, $skip_on_fail ) = @_;

   return fixture(
      name => "user_with_push_rule_fixture($action)",
      requires => [ local_user_fixture() ],
      setup => sub {
         my ( $user ) = @_;

         matrix_add_push_rule( $user, 'global', 'content', 'anything', {
            pattern => "*",
            actions => [ $action ]
         })->then_with_f(
            sub { # done
               Future->done( $user );
            },
            http => sub {  # catch http
               my ( $f, undef, undef, $response ) = @_;
               log_if_fail "push rule fail", $response;
               if ( $skip_on_fail && $response && $response->code == 400 ) {
                  # assume the server doesn't support this
                  die "SKIP: server does not support $action action";
               }
               # otherwise propagate the original result
               return $f;
            },
         );
      },
   );
}

foreach my $action_and_counter (
   [ "notify", "notification_count" ],
   [ "org.matrix.msc2625.mark_unread", "org.matrix.msc2625.unread_count" ]
) {
   my ( $action, $counter ) = @$action_and_counter;
   test "Messages that $action from another user increment $counter",
      requires => [
         user_with_push_rule_fixture(
            $action,
            $action eq "org.matrix.msc2625.mark_unread"
         ),
         local_user_fixture(),
         qw( can_sync )
      ],

      check    => sub {
         my ( $user1, $user2 ) = @_;

         my $room_id;

         matrix_create_room( $user1 )
         ->then( sub {
            ($room_id) = @_;

            matrix_join_room( $user2, $room_id );
         })->then( sub {
            matrix_send_room_text_message( $user2, $room_id,
               body => "Test message 1",
            );
         })->then( sub {
            my ( $event_id ) = @_;

            matrix_advance_room_receipt_synced( $user1, $room_id, "m.read" => $event_id );
         })->then( sub {
            matrix_sync( $user1 );
         })->then( sub {
            my ( $body ) = @_;

            my $room = $body->{rooms}{join}{$room_id};
            log_if_fail "room in sync response", $room;

            assert_json_keys( $room, "unread_notifications" );
            my $unread = $room->{unread_notifications};
            assert_json_keys( $unread, $counter );

            $unread->{$counter} == 0
               or die "Expected $counter to be 0";

            matrix_send_room_text_message_synced( $user2, $room_id,
               body => "Test message 2",
            );
         })->then( sub {
            matrix_sync( $user1 );
         })->then( sub {
            my ( $body ) = @_;

            my $room = $body->{rooms}{join}{$room_id};

            assert_json_keys( $room, "unread_notifications" );
            my $unread = $room->{unread_notifications};
            assert_json_keys( $unread, $counter );

            $unread->{$counter} == 1
               or die "Expected $counter to be 1";

            Future->done(1);
         });
      };
}

test "Messages that highlight from another user increment unread highlight count",
   requires => [ local_user_fixture( with_events => 0 ),
		 local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user1, $user2 ) = @_;

      my $room_id;

      matrix_add_push_rule( $user1, 'global', 'content', 'anything', {
         pattern => "*",
         actions => [ "notify", { set_tweak => "highlight", value => JSON::true } ]
      })->then( sub {
         matrix_create_room( $user1 );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_join_room( $user2, $room_id );
      })->then( sub {
         matrix_send_room_text_message( $user2, $room_id,
            body => "Test message 1",
         );
      })->then( sub {
         my ( $event_id ) = @_;

         matrix_advance_room_receipt_synced( $user1, $room_id, "m.read" => $event_id );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         assert_json_keys( $room, "unread_notifications" );
         my $unread = $room->{unread_notifications};
         assert_json_keys( $unread, "highlight_count" );

         $unread->{highlight_count} == 0
            or die "Expected unread highlight count to be 0";

         matrix_send_room_text_message_synced( $user2, $room_id,
            body => "Test message 2",
         );
      })->then( sub {
         matrix_sync( $user1 );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         assert_json_keys( $room, "unread_notifications" );
         my $unread = $room->{unread_notifications};
         assert_json_keys( $unread, "highlight_count" );

         $unread->{highlight_count} == 1
            or die "Expected unread highlight count to be 1";

         Future->done(1);
      })
   };
