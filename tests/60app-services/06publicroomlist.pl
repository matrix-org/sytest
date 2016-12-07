use constant AS_PREFIX => "/_matrix/app/unstable";


test "AS can publish rooms in their own list",
   requires => [ $main::AS_USER[0], $main::APPSERV[0], local_user_fixture() ],

   do => sub {
      my ( $as_user, $appserv, $local_user ) = @_;

      my $room_id;
      my $appserv_id = $appserv->info->id;
      my $network_id = "random-network";

      # FIXME: We should really query this through the thirdparty protocols API,
      # as this relies on an internal synapse implementation detail.
      my $instance_id = "$appserv_id|$network_id";

      matrix_create_room( $local_user,
         visibility      => "private",
         preset          => "public_chat",
         name            => "Test Name",
         topic           => "Test Topic",
      )->then( sub {
         ( $room_id ) = @_;

         log_if_fail "Room ID", $room_id;

         do_request_json_for( $as_user,
            method => "PUT",
            uri    => "/r0/directory/list/appservice/$network_id/$room_id",

            content => {
               visibility => "public",
            }
         )
      })->then( sub {
         do_request_json_for( $local_user,
            method => "GET",
            uri    => "/r0/publicRooms",
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            and die "AS public room in main list";

         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/publicRooms",

            content => { third_party_instance_id => $instance_id, limit => 1000000 }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "AS public room is not in the AS list";

         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/publicRooms",

            content => { include_all_networks => "true", limit => 1000000 }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "AS public room is not in the full room list";

         do_request_json_for( $as_user,
            method => "DELETE",
            uri    => "/r0/directory/list/appservice/$network_id/$room_id",
         )
      })->then( sub {
         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/publicRooms",

            content => { third_party_instance_id => $instance_id, limit => 1000000 }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            and die "AS public room in AS list after deletion";

         Future->done( 1 );
      })
   };


test "AS and main public room lists are separate",
   requires => [ $main::AS_USER[0], $main::APPSERV[0], local_user_fixture() ],

   do => sub {
      my ( $as_user, $appserv, $local_user ) = @_;

      my $room_id;
      my $appserv_id = $appserv->info->id;
      my $network_id = "random-network";

      # FIXME: We should really query this through the thirdparty protocols API,
      # as this relies on an internal synapse implementation detail.
      my $instance_id = "$appserv_id|$network_id";

      matrix_create_room( $local_user,
         visibility      => "private",
         preset          => "public_chat",
         name            => "Test Name",
         topic           => "Test Topic",
      )->then( sub {
         ( $room_id ) = @_;

         log_if_fail "Room ID", $room_id;

         do_request_json_for( $as_user,
            method => "PUT",
            uri    => "/r0/directory/list/appservice/$network_id/$room_id",

            content => {
               visibility => "public",
            }
         )
      })->then( sub {
         do_request_json_for( $local_user,
            method => "PUT",
            uri    => "/r0/directory/list/room/$room_id",

            content => {
               visibility => "public",
            }
         )
      })->then( sub {
         do_request_json_for( $local_user,
            method => "GET",
            uri    => "/r0/publicRooms",
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Room not in main list";

         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/publicRooms",

            content => { third_party_instance_id => $instance_id, limit => 1000000 }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Room is not in the AS list";

         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/publicRooms",

            content => { include_all_networks => "true", limit => 1000000 }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Public room is not in the full room list";

         do_request_json_for( $as_user,
            method => "DELETE",
            uri    => "/r0/directory/list/appservice/$network_id/$room_id",
         )
      })->then( sub {
         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/publicRooms",

            content => { third_party_instance_id => $instance_id, limit => 1000000 }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            and die "Room in AS list after deletion";

         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/publicRooms",

            content => { limit => 1000000 }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Room not in main list after AS list deletion";

         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/publicRooms",

            content => { include_all_networks => "true", limit => 1000000 }
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( chunk ) );

         any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
            or die "Room is not in the full room list after AS deletion";

         Future->done( 1 );
      })
   };
