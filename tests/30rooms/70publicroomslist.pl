test "Name/topic keys are correct",
   requires => [ $main::API_CLIENTS[0], local_user_fixture() ],

   check => sub {
      my ( $http, $user ) = @_;

      my %rooms = (
         publicroomalias_no_name => {},
         publicroomalias_with_name => {
            name => "name_1",
         },
         publicroomalias_with_topic => {
            topic => "topic_1",
         },
         publicroomalias_with_name_topic => {
            name => "name_2",
            topic => "topic_2",
         },
      );

      Future->needs_all( map {
         my $alias_local = $_;
         my $room = $rooms{$alias_local};

         matrix_create_room( $user,
            visibility      => "public",
            room_alias_name => $alias_local,
            name            => $room->{name},
            topic           => $room->{topic},
         )
      } keys %rooms )
      ->then( sub {
         repeat_until_true {
            $http->do_request_json(
               method => "GET",
               uri    => "/r0/publicRooms",
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "publicRooms", $body;

               assert_json_keys( $body, qw( chunk ));
               assert_json_list( $body->{chunk} );

               my %isOK = map {
                  $_ => 0,
               } keys ( %rooms );

               foreach my $room ( @{ $body->{chunk} } ) {
                  assert_json_keys( $room,
                     qw( world_readable guest_can_join num_joined_members )
                  );

                  my $name = $room->{name};
                  my $topic = $room->{topic};
                  my $canonical_alias = $room->{canonical_alias};

                  my $aliases = $room->{aliases};
                  if( not defined $aliases ) {
                     next;
                  }

                  foreach my $alias ( @{$aliases} ) {
                     foreach my $alias_local ( keys %rooms ) {
                        $alias =~ m/^\Q#$alias_local:\E/ or next;

                        my $room_config = $rooms{$alias_local};

                        log_if_fail "Alias", $alias_local;
                        log_if_fail "Room", $room;

                        assert_eq( $canonical_alias, $alias, "Incorrect canonical_alias" );
                        assert_eq( $room->{num_joined_members}, 1, "Incorrect member count" );

                        # The rooms should get created "atomically", so we should never
                        # see any out of the public rooms list in the wrong state. If
                        # we see a room we expect it to already be in the right state.

                        if( defined $name ) {
                           assert_eq( $room_config->{name}, $name, 'room name' );
                        }
                        else {
                           defined $room_config->{name} and die "Expected not to find a name";
                        }

                        if( defined $topic ) {
                           assert_eq( $room_config->{topic}, $topic, 'room topic' );
                        }
                        else {
                           defined $room_config->{topic} and die "Expected not to find a topic";
                        }

                        $isOK{$alias_local} = 1;
                     }
                  }
               }

               Future->done( all { $isOK{$_} } keys %isOK );
            });
         };
      });
   };

test "Can get remote public room list",
   requires => [ $main::HOMESERVER_INFO[0], local_user_fixture(), remote_user_fixture() ],

   check => sub {
      my ( $info, $local_user, $remote_user ) = @_;
      my $first_home_server = $info->server_name;

      my $room_id;

      matrix_create_room( $local_user,
         visibility      => "public",
         name            => "Test Name",
         topic           => "Test Topic",
      )->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $remote_user,
            method => "GET",
            uri    => "/r0/publicRooms",

            params => { server => $first_home_server },
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "Body", $body;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Remote room list did not include expected room";

         Future->done( 1 );
      })
   };
