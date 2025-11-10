test "Can get remote public room list",
   requires => [ $main::HOMESERVER_INFO[0], local_user_fixture(), remote_user_fixture() ],

   check => sub {
      my ( $info, $local_user, $remote_user ) = @_;
      my $first_home_server = $info->server_name;

      my $room_id;

      matrix_create_room_synced( $local_user,
         visibility      => "public",
         name            => "Test Name",
         topic           => "Test Topic",
      )->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $remote_user,
            method => "GET",
            uri    => "/v3/publicRooms",

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


test "Can paginate public room list",
   # this test can take a while, because we create 10 rooms, which is quite slow
   # (https://github.com/matrix-org/synapse/issues/6068)
   timeout => 20,

   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      my $num_rooms;
      my $next_batch;
      my $prev_batch;

      # A hash from room ID to number of times we saw the room.
      my %counts;

      # First we fill up the room list a bit (note there will probably already
      # be entries in it).
      ( try_repeat {
         my ($n) = @_;
         matrix_create_room_synced( $user, visibility => "public" )->on_done( sub {
            my ( $body ) = @_;
            log_if_fail "Created room $n", $body;
         });
      } foreach => [ 1 .. 10 ] )->then( sub {
         # Now we do an un-limited query to work out the number of rooms we
         # expect.

         do_request_json_for( $user,
            method => "GET",
            uri    => "/v3/publicRooms",
         )
      })->then( sub {
         my ( $body ) = @_;

         log_if_fail "initial /publicRooms response", $body;

         $num_rooms = scalar( @{ $body->{chunk} } );

         # Now we iterate through the room list, recording how often we see a
         # room.
         try_repeat {
            do_request_json_for( $user,
               method => "POST",
               uri    => "/v3/publicRooms",

               content => { limit => 3, since => $next_batch },
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "Forwards body", $body;

               scalar( @{ $body->{chunk} } ) <= 3 or die "Got too many results";

               foreach my $chunk ( @{ $body->{chunk} } ) {
                  $counts{ $chunk->{room_id} } += 1;
               }

               $next_batch = $body->{next_batch};
               $prev_batch = $body->{prev_batch};

               Future->done( 1 );
            })
         } until => sub { !$next_batch };
      })->then( sub {
         log_if_fail "Forward counts", \%counts;

         # We expect to see every room exactly once.
         assert_eq scalar( keys %counts ), $num_rooms, "number of rooms";
         all { $_ == 1 } values %counts or die "Saw a room more than once iterating forwards";

         # We now reset the counts and try iterating backwards, ensuring we see
         # all but the last three rooms again.
         # Reset counts
         %counts = ();

         try_repeat {
            do_request_json_for( $user,
               method => "POST",
               uri    => "/v3/publicRooms",

               content => { limit => 3, since => $prev_batch },
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "Backwards body", $body;

               scalar( @{ $body->{chunk} } ) <= 3 or die "Got too many results";

               foreach my $chunk ( @{ $body->{chunk} } ) {
                  $counts{ $chunk->{room_id} } += 1;
               }

               $next_batch = $body->{next_batch};
               $prev_batch = $body->{prev_batch};

               Future->done( 1 );
            })
         } until => sub { !$prev_batch };
      })->then( sub {
         log_if_fail "Backward counts", \%counts;

         # We expect to see all bar the final chunk of rooms exactly once (which
         # may be up to three rooms)
         scalar( keys %counts ) >= $num_rooms - 3 or die "Saw too few rooms paginating backwards";
         all { $_ == 1 } values %counts or die "Saw a room more than once iterating backwards";

         Future->done( 1 );
      })
   };

test "Asking for a remote rooms list, but supplying the local server's name, returns the local rooms list",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $local_user ) = @_;

      my $room_id;

      matrix_create_room_synced( $local_user,
         visibility      => "public",
         name            => "Test Name",
         topic           => "Test Topic Wibbles",
      )->then( sub {
         ( $room_id ) = @_;

         retry_until_success {
            do_request_json_for( $local_user,
               method => "POST",
               uri    => "/v3/publicRooms",

               # Ask the local server for a remote room list, but supply the local server's server_name
               # Server should return the local public rooms list
               params => {
                  server => $local_user->server_name,
               },

               content => {
                  filter => {
                     generic_search_term => "wibbles",  # Search case insensitively
                  }
               },
            )->then( sub {
               my ( $body ) = @_;

               log_if_fail "Body", $body;

               assert_json_keys( $body, qw( chunk ) );

               # We only expect to find a single result
               assert_eq scalar @{ $body->{chunk} }, 1, "number of results";
               assert_eq $body->{chunk}[0]{room_id}, $room_id, "room id";

               Future->done( 1 );
            })->on_fail( sub {
               my ( $exc ) = @_;
               chomp $exc;
               log_if_fail "Failed to search room dir: $exc";
            });
         }
      })
   };
