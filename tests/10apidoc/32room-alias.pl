my $user_fixture = local_user_fixture();

my $room_fixture = fixture(
   requires => [ $user_fixture ],

   setup => sub {
      my ( $user ) = @_;

      matrix_create_room( $user )->then( sub {
         my ( $room_id, undef ) = @_;
         Future->done( $room_id );  # Don't return the alias
      });
   },
);

test "PUT /directory/room/:room_alias creates alias",
   requires => [ $user_fixture, $room_fixture, room_alias_fixture() ],

   proves => [qw( can_create_room_alias can_lookup_room_alias )],

   do => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/directory/room/$room_alias",

         content => {
            room_id => $room_id,
         },
      );
   },

   check => sub {
      my ( $user, $room_id, $room_alias ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id servers ));
         assert_json_list( $body->{servers} );

         $body->{room_id} eq $room_id or die "Expected room_id";

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/aliases lists aliases",
   requires => [ $user_fixture, room_alias_fixture(), qw( can_create_room_alias )],

   do => sub {
      my ( $user, $room_alias ) = @_;
      my ( $room_id );

      matrix_create_room( $user )->then( sub {
         ( $room_id ) = @_;

         # the list should be empty initially
         do_request_json_for(
            $user,
            method => "GET",
            uri => "/r0/rooms/$room_id/aliases",
         );
      })->then( sub {
         my ( $res ) = @_;
         log_if_fail "response from /aliases before change:", $res;

         assert_json_keys( $res, qw( aliases ));
         assert_json_empty_list( $res->{aliases} );

         # now add an alias
         do_request_json_for(
            $user,
            method => "PUT",
            uri    => "/r0/directory/room/$room_alias",
            content => { room_id => $room_id },
         );
      })->then( sub {
         my ( $res ) = @_;
         log_if_fail "response from PUT /directory:", $res;

         # ... and recheck. Might need to try this a few times while the caches
         # get flushed.
         retry_until_success {
            my ( $iter ) = @_;
            return do_request_json_for(
               $user,
               method => "GET",
               uri => "/r0/rooms/$room_id/aliases",
            )->then( sub {
               my ( $res ) = @_;
               log_if_fail "$iter: response from /aliases", $res;
               assert_json_keys( $res, qw( aliases ));
               assert_deeply_eq($res->{aliases}, [ $room_alias ]);
               Future->done;
            });
         }
      });
   };
