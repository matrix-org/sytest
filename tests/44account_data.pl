test "Can add account data",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_add_account_data( $user, "my.test.type", {} );
   };


test "Can add account data to room",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_add_room_account_data( $user, $room_id, "my.test.type", {} );
   };


sub check_one_account_data_event
{
   my ( $account_data_events, $expected_type, $cats_or_rats ) = @_;

   log_if_fail "account data", $account_data_events;

   @{ $account_data_events } == 1 or die "Expected only one event";

   my $event = $account_data_events->[0];
   assert_json_keys($event, qw( type content ));

   $event->{type} eq $expected_type
      or die "Unexpected event type, wanted $expected_type";

   $event->{content}{cats_or_rats} eq $cats_or_rats
      or die "Unexpected event content, wanted $cats_or_rats";
}


sub setup_account_data
{
   my ( $user, $room_id ) = @_;

   Future->needs_all(
      matrix_add_account_data( $user, "my.test.type", {
         cats_or_rats => "frogs",
      }),
      matrix_add_room_account_data( $user, $room_id, "my.test.type", {
         cats_or_rats => "dogs",
      }),
   )->then( sub {
      Future->needs_all(
         matrix_add_account_data( $user, "my.test.type", {
            cats_or_rats => "cats",
         }),
         matrix_add_room_account_data( $user, $room_id, "my.test.type", {
            cats_or_rats => "rats",
         }),
      );
   });
}


test "Can get account data without syncing",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      setup_account_data( $user, $room_id )->then( sub {
         matrix_get_account_data( $user, "my.test.type" );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys($body, qw( type cats_or_rats ));
         $body->{cats_or_rats} eq "cats"
            or die "Unexpected event content, wanted cats";

         Future->done(1);
      });
   };


test "Can get room account data without syncing",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      setup_account_data( $user, $room_id )->then( sub {
         matrix_get_room_account_data( $user, $room_id, "my.test.type" );
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys($body, qw( type cats_or_rats ));
         $body->{cats_or_rats} eq "rats"
            or die "Unexpected event content, wanted rats";

         Future->done(1);
      });
   };


test "Latest account data comes down in /initialSync",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      setup_account_data( $user, $room_id )->then( sub {
         matrix_initialsync( $user );
      })->then( sub {
         my ( $body ) = @_;

         check_one_account_data_event(
            $body->{account_data}, "my.test.type", "cats"
         );

         check_one_account_data_event(
            $body->{rooms}[0]{account_data}, "my.test.type", "rats"
         );

         Future->done(1);
      });
   };


test "Latest account data comes down in room initialSync",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      setup_account_data( $user, $room_id )->then( sub {
         matrix_initialsync_room( $user, $room_id );
      })->then( sub {
         my ( $body ) = @_;

         check_one_account_data_event(
            $body->{account_data}, "my.test.type", "rats"
         );

         Future->done(1);
      });
   };


test "Account data appears in v1 /events stream",
   requires => [ local_user_fixture( with_events => 1 ) ],

   check => sub {
      my ( $user ) = @_;

      Future->needs_all(
         await_event_for( $user, filter => sub {
            my ( $event ) = @_;

            return $event->{type} eq "my.test.type"
               && $event->{content}{cats_or_rats} eq "cats";
         }),
         matrix_add_account_data( $user, "my.test.type", {
            cats_or_rats => "cats",
         }),
      );
   };


test "Room account data appears in v1 /events stream",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      flush_events_for( $user )
      ->then( sub {
         Future->needs_all(
            await_event_for( $user, filter => sub {
               my ( $event ) = @_;

               return $event->{type} eq "my.test.type"
                  && $event->{content}{cats_or_rats} eq "rats"
                  && $event->{room_id} eq $room_id;
            }),
            matrix_add_room_account_data( $user, $room_id, "my.test.type", {
               cats_or_rats => "rats",
            }),
         );
      });
   };


test "Latest account data appears in v2 /sync",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      setup_account_data( $user, $room_id )->then( sub {
         # Send and wait for a text message so that we know that /sync is ready
         matrix_send_room_text_message_synced( $user, $room_id, body => "synced");
      })->then( sub {
         matrix_sync( $user, filter => '{"account_data":{"types":["my.test.type"]}}' );
      })->then( sub {
         my ( $body ) = @_;

         check_one_account_data_event(
            $body->{account_data}{events}, "my.test.type", "cats"
         );

         check_one_account_data_event(
            $body->{rooms}{join}{$room_id}{account_data}{events},
            "my.test.type", "rats"
         );

         Future->done(1);
      });
   };

sub setup_incremental_account_data
{
   my ( $user, $room_id, $type, $top_animal, $room_animal ) = @_;

   Future->needs_all(
      matrix_add_account_data( $user, $type, {
         cats_or_rats => $top_animal,
      }),
      matrix_add_room_account_data( $user, $room_id, $type, {
         cats_or_rats => $room_animal,
      })
   );
}

test "New account data appears in incremental v2 /sync",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      Future->needs_all(
         setup_incremental_account_data(
            $user, $room_id, "my.unchanging.type", "lions", "tigers"
         ),
         setup_incremental_account_data(
            $user, $room_id, "my.changing.type", "dogs", "frogs"
         ),
      )->then( sub {
         # Send and wait for a text message so that we know that /sync is ready
         matrix_send_room_text_message_synced( $user, $room_id, body => "synced");
      })->then( sub {
         matrix_sync( $user );
      })->then( sub {
         setup_incremental_account_data(
            $user, $room_id, "my.changing.type", "cats", "rats"
         ),
      })->then( sub {
         # Send and wait for a text message so that we know that /sync is ready
         matrix_send_room_text_message_synced( $user, $room_id, body => "synced");
      })->then( sub {
         matrix_sync_again( $user );
      })->then( sub {
         my ( $body ) = @_;

         check_one_account_data_event(
            $body->{account_data}{events}, "my.changing.type", "cats"
         );

         check_one_account_data_event(
            $body->{rooms}{join}{$room_id}{account_data}{events},
            "my.changing.type", "rats"
         );

         Future->done(1);
      });
   };
