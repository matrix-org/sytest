use JSON qw( encode_json );

test "Can pass a JSON filter as a query parameter",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      my ( $room_id );

      matrix_create_room_and_wait_for_sync( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => encode_json( {
            room => {
               state => { types => [ "m.room.member" ] },
               timeline => { limit => 0 },
            }
         }));
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         assert_json_empty_list( $room->{timeline}{events} );

         @{ $room->{state}{events} } == 1
            or die "Expected a single state event because of the filter";

         $room->{state}{events}[0]{type} eq "m.room.member"
            or die "Expected a single member event because of the filter";

         Future->done(1);
      });
   };
