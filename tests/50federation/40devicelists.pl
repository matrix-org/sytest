test "Local device key changes appear in v2 /sync",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER, federation_user_id_fixture(), room_alias_name_fixture() ],

   check => sub {
      my ( $user, $inbound_server, $creator_id, $room_alias_name ) = @_;

      my ( $room_id );

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $room_alias = "#$room_alias_name:$local_server_name";

      my $prev_stream_id;

      my $room = $datastore->create_room(
         creator => $creator_id,
         alias   => $room_alias,
      );

      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/join/$room_alias",

         content => {},
      )->then( sub {
         Future->needs_all(
            $inbound_server->await_edu( "m.device_list_update", sub {1} )
            ->then( sub {
               my ( $edu ) = @_;
               log_if_fail "Received edu", $edu;

               assert_json_keys( $edu->{content}, qw( user_id device_id stream_id ) );
               assert_eq( $edu->{content}{user_id}, $user->user_id );
               assert_eq( $edu->{content}{device_id}, $user->device_id );

               $prev_stream_id = $edu->{content}{stream_id};

               Future->done(1);
            }),
            do_request_json_for( $user,
               method  => "POST",
               uri     => "/unstable/keys/upload",
               content => {
                  device_keys => {
                     user_id => $user->user_id,
                     device_id => $user->device_id,
                  },
                  one_time_keys => {
                     "my_algorithm:my_id_1", "my+base64+key"
                  }
               }
            )
         )
      })->then( sub {
         Future->needs_all(
            $inbound_server->await_edu( "m.device_list_update", sub {1} )
            ->then( sub {
               my ( $edu ) = @_;
               log_if_fail "Received edu", $edu;

               assert_json_keys( $edu->{content}, qw( user_id device_id stream_id prev_id ) );
               assert_eq( $edu->{content}{user_id}, $user->user_id );
               assert_eq( $edu->{content}{device_id}, $user->device_id );
               assert_deeply_eq( $edu->{content}{prev_id}, [$prev_stream_id] );

               Future->done(1);
            }),
            do_request_json_for( $user,
               method  => "POST",
               uri     => "/unstable/keys/upload",
               content => {
                  device_keys => {
                     user_id => $user->user_id,
                     device_id => $user->device_id,
                  },
                  one_time_keys => {
                     "my_algorithm:my_id_1", "my+second+base64+key"
                  }
               }
            )
         )
      });
   };
