use JSON qw( encode_json );

test "Can pass a JSON filter as a query parameter",
   requires => [ local_user_and_room_fixtures() ],

   check => sub {
      my ( $user, $room_id ) = @_;

      matrix_sync( $user, filter => encode_json( {
         room => {
            state => { types => [ "m.room.member" ] },
            timeline => { limit => 0 },
         }
      }))->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         @{ $room->{timeline}{events} } == 0
            or die "Expected no timeline events because limit is 0";

         @{ $room->{state}{events} } == 1
            or die "Expected a single state event because of the filter";

         $room->{state}{events}[0]{type} eq "m.room.member"
            or die "Expected a single member event because of the filter";

         Future->done(1);
      });
   };
