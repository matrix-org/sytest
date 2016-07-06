use Future::Utils qw( try_repeat );

test "/whois",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      my $user;

      # Register a user, rather than using a fixture, because we want to very
      # tightly control the actions taken by that user.
      # Conceivably this API may change based on the number of API calls the
      # user made, for instance.
      matrix_register_user( $http, "admin" )
      ->then( sub {
         ( $user ) = @_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/r0/admin/whois/".$user->user_id,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( devices user_id ) );
         assert_eq( $body->{user_id}, $user->user_id, "user_id" );
         assert_json_object( $body->{devices} );

         foreach my $value ( values %{ $body->{devices} } ) {
            assert_json_keys( $value, "sessions" );
            assert_json_list( $value->{sessions} );
            assert_json_keys( $value->{sessions}[0], "connections" );
            assert_json_list( $value->{sessions}[0]{connections} );
            assert_json_keys( $value->{sessions}[0]{connections}[0], qw( ip last_seen user_agent ) );
         }

         Future->done( 1 );
      });
   };

test "/purge_history",
   requires => [ local_admin_fixture(), local_user_and_room_fixtures() ],

   do => sub {
      my ( $admin, $user, $room_id ) = @_;

      my $last_event_id;

      matrix_put_room_state( $user, $room_id,
         type    => "m.room.name",
         content => { name => "A room name" },
      )->then( sub {
         try_repeat( sub {
            my $msgnum = $_[0];

            matrix_send_room_text_message_synced( $user, $room_id,
               body => "Message $msgnum",
            )
         }, foreach => [ 1 .. 10 ])
      })->then( sub {
         ( $last_event_id ) = @_;

         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/admin/purge_history/$room_id/$last_event_id",
            content => {}
         )->main::expect_http_403;  # Must be server admin
      })->then( sub {
         matrix_sync( $user )
      })->then( sub {
         do_request_json_for( $admin,
            method  => "POST",
            uri     => "/r0/admin/purge_history/$room_id/$last_event_id",
            content => {}
         )
      })->then( sub {
         matrix_sync_again( $user )
      })->then( sub {
         matrix_sync( $user )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body->{rooms}{join}, $room_id );
         my $room =  $body->{rooms}{join}{$room_id};

         log_if_fail( "Room", $room->{timeline}{events} );

         # The only message event should be the last one.
         all {
            $_->{type} ne "m.room.message" || $_->{event_id} eq $last_event_id
         } @{ $room->{timeline}{events} } or die "Expected no message events";

         foreach my $expected_type( qw(
            m.room.create
            m.room.member
            m.room.power_levels
            m.room.name
         ) ) {
            any { $_->{type} eq $expected_type } @{ $room->{state}{events} }
               or die "Expected state event of type $expected_type";
         }

         Future->done( 1 );
      })
   };
