# Copied from 30rooms/70publicroomslist.pl, modified to test the federation publicRooms API
test "Name/topic keys are correct",
   requires => [ local_user_fixture(), $main::OUTBOUND_CLIENT ],

   check => sub {
      my ( $user, $client ) = @_;

      my $server_name = $user->server_name;

      my %rooms = (
         publicroomalias_no_name_30_70_test => {},
         publicroomalias_with_name_30_70_test => {
            name => "name_1",
         },
         publicroomalias_with_topic_30_70_test => {
            topic => "topic_1",
         },
         publicroomalias_with_name_topic_30_70_test => {
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
            %$room,
         )
      } keys %rooms )
      ->then( sub {
         $client->do_request_json(
            method   => "GET",
            hostname => $server_name,
            uri      => "/v1/publicRooms",
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "publicRooms", $body;

         assert_json_keys( $body, qw( chunk ));
         assert_json_list( $body->{chunk} );

         my %seen = map {
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
            defined $aliases or next;

            foreach my $alias ( @{$aliases} ) {
               foreach my $alias_local ( keys %rooms ) {
                  $alias =~ m/^\Q#$alias_local:\E/ or next;

                  my $room_config = $rooms{$alias_local};

                  log_if_fail "Alias", $alias_local;
                  log_if_fail "Room", $room;

                  assert_eq( $canonical_alias, $alias, "canonical alias" );
                  assert_eq( $room->{num_joined_members}, 1, "num_joined_members" );

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
                  last;
               }
            }
         }

         foreach my $key ( keys %seen ) {
            $seen{$key} or die "Did not find a /publicRooms result for $key";
         }

         Future->done(1);
      })
   }
