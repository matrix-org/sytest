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
         $http->do_request_json(
            method => "GET",
            uri    => "/r0/publicRooms",
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "publicRooms", $body;

         assert_json_keys( $body, qw( start end chunk ));
         assert_json_list( $body->{chunk} );

         my %seen = map {
            $_ => 0,
         } keys ( %rooms );

         foreach my $room ( @{ $body->{chunk} } ) {
            assert_json_keys( $room,
               qw( world_readable guest_can_join num_joined_members aliases )
            );

            my $name = $room->{name};
            my $topic = $room->{topic};
            my $canonical_alias = $room->{canonical_alias};

            my $aliases = $room->{aliases};
            foreach my $alias ( @{$aliases} ) {
               foreach my $alias_local ( keys %rooms ) {
                  $alias =~ m/^\Q#$alias_local:\E/ or next;

                  my $room_config = $rooms{$alias_local};

                  log_if_fail "Alias", $alias_local;
                  log_if_fail "Room", $room;

                  assert_eq( $canonical_alias, $alias, "Incorrect canonical_alias" );
                  assert_eq( $room->{num_joined_members}, 1, "Incorrect member count" );

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

                  $seen{$alias_local} = 1;
               }
            }
         }

         foreach my $key ( keys %seen ) {
            $seen{$key} or die "Did not find a /publicRooms result for $key";
         }

         Future->done(1);
      })
   }
