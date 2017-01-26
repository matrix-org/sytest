test "Local device key changes get to remote servers",
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


test "Server correctly handles incoming m.device_list_update",
   requires => [ local_user_fixture(), $main::INBOUND_SERVER, $main::OUTBOUND_CLIENT,
                 $main::HOMESERVER_INFO[0],  federation_user_id_fixture(),
                 room_alias_name_fixture() ],

   check => sub {
      my ( $user, $inbound_server, $outbound_client, $info, $creator_id, $room_alias_name ) = @_;

      my ( $room_id );

      my $local_server_name = $info->server_name;

      my $remote_server_name = $inbound_server->server_name;
      my $datastore          = $inbound_server->datastore;

      my $room_alias = "#$room_alias_name:$remote_server_name";

      my $device_id = "random_device_id";

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
            $inbound_server->await_request_user_devices( $creator_id )
            ->then( sub {
               my ( $req, undef ) = @_;

               assert_eq( $req->method, "GET", 'request method' );

                $req->respond_json( {
                   user_id   => $creator_id,
                   stream_id => 1,
                   devices   => [ {
                      device_id => $device_id,

                      keys => {
                        device_keys => {}
                     }
                   } ]
                } );

               Future->done(1);
            }),
            $outbound_client->send_edu(
               edu_type    => "m.device_list_update",
               destination => $local_server_name,
               content     => {
                  user_id   => $creator_id,
                  device_id => $device_id,
                  stream_id => 1,

                  keys => {
                     device_keys => {}
                  }
               }
            )
         )
      })->then( sub {
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/unstable/keys/query",
            content => {
               device_keys => {
                  $creator_id => [ "random_device_id" ],
               }
            }
         )
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "query response", $content;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $creator_id );

         my $alice_keys = $device_keys->{ $creator_id };
         assert_json_keys( $alice_keys, $device_id );

         $outbound_client->send_edu(
            edu_type    => "m.device_list_update",
            destination => $local_server_name,
            content     => {
               user_id             => $creator_id,
               device_id           => "random_device_id",
               device_display_name => "test display name",
               prev_id             => [ 1 ],
               stream_id           => 2,

               keys => {
                  device_keys => {}
               }
            }
         )
      })->then( sub {
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/unstable/keys/query",
            content => {
               device_keys => {
                  $creator_id => [ "random_device_id" ],
               }
            }
         )
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "query response", $content;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $creator_id );

         my $alice_keys = $device_keys->{ $creator_id };
         assert_json_keys( $alice_keys, $device_id );

         my $alice_device_keys = $alice_keys->{ $device_id };
         assert_json_keys( $alice_device_keys, "unsigned" );

         my $unsigned = $alice_device_keys->{unsigned};

         assert_eq( $unsigned->{device_display_name}, "test display name" );

         Future->done( 1 )
      });
   };
