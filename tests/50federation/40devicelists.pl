test "Local device key changes get to remote servers",
   requires => [ local_user_fixture(),
                 $main::INBOUND_SERVER, federation_user_id_fixture(), room_alias_name_fixture() ],

   check => sub {
      my ( $user, $inbound_server, $creator_id, $room_alias_name ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $room_alias = "#$room_alias_name:$local_server_name";

      my $prev_stream_id;

      $datastore->create_room(
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
            matrix_put_e2e_keys( $user )
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
            matrix_put_e2e_keys( $user, device_keys => { updated => "keys" } )
         )
      });
   };


test "Server correctly handles incoming m.device_list_update",
   requires => [ local_user_fixture(),
                 $main::INBOUND_SERVER, $main::OUTBOUND_CLIENT,
                 federation_user_id_fixture(),
                 room_alias_name_fixture() ],

   check => sub {
      my ( $user, $inbound_server, $outbound_client, $creator_id, $room_alias_name ) = @_;

      my $local_server_name = $user->server_name;

      my $remote_server_name = $inbound_server->server_name;
      my $datastore          = $inbound_server->datastore;

      my $room_alias = "#$room_alias_name:$remote_server_name";

      my $device_id = "random_device_id";

      $datastore->create_room(
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
            uri     => "/r0/keys/query",
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
            uri     => "/r0/keys/query",
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


test "Server correctly resyncs when client query keys and there is no remote cache",
   requires => [ $main::INBOUND_SERVER, federated_rooms_fixture() ],

   check => sub {
      my ( $inbound_server, $user, $federated_user_id, undef) = @_;

      # We return two devices, as there was a bug in synapse which correctly
      # handled returning one device but not two.
      my $device_id1 = "random_device_id1";
      my $device_id2 = "random_device_id2";

      # We set up a situation where sytest joins a room with a user without
      # relaying any device keys, and then a client of synapse requests the keys
      # for that user. This should cause synapse to do a resync and cache those
      # keys correctly.
      Future->needs_all(
         $inbound_server->await_request_user_devices( $federated_user_id )
         ->then( sub {
            my ( $req, undef ) = @_;

            assert_eq( $req->method, "GET", 'request method' );

            $req->respond_json( {
               user_id   => $federated_user_id,
               stream_id => 1,
               devices   => [
                  {
                     device_id => $device_id1,
                     keys      => { device_keys => {} },
                  },
                  {
                     device_id => $device_id2,
                     keys      => { device_keys => {} },
                  },
               ],
            } );
            Future->done(1);
         }),
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/keys/query",
            content => {
               device_keys => {
                  $federated_user_id => [],
               },
            },
         ),
      )->then( sub {
         my ( $first, $content ) = @_;

         log_if_fail "query response", $content;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $federated_user_id );

         my $alice_keys = $device_keys->{ $federated_user_id };
         assert_json_keys( $alice_keys, ( $device_id1, $device_id2 ) );

         Future->done( 1 )
      });
   };


test "Server correctly resyncs when server leaves and rejoins a room",
   requires => [ $main::INBOUND_SERVER, federated_rooms_fixture() ],

   check => sub {
      my ( $inbound_server, $user, $federated_user_id, $room ) = @_;

      # At first the server shares a room with the federated user, who at that
      # point has a single device. The server will then leave and then rejoin
      # the room. In the mean time the federated user has added a device, but
      # won't have poked the server as they didn't share a room.
      #
      # When the server rejoins the subsequent calls by clients to fetch keys
      # should result in the server resyncing the device lists.
      my $device_id1 = "random_device_id1";
      my $device_id2 = "random_device_id2";

      Future->needs_all(
         $inbound_server->await_request_user_devices( $federated_user_id )
         ->then( sub {
            my ( $req, undef ) = @_;

            assert_eq( $req->method, "GET", 'request method' );

            $req->respond_json( {
               user_id   => $federated_user_id,
               stream_id => 1,
               devices   => [
                  {
                     device_id => $device_id1,
                     keys      => { device_keys => {} },
                  },
               ],
            } );
            Future->done(1);
         }),
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/keys/query",
            content => {
               device_keys => {
                  $federated_user_id => [],
               },
            },
         ),
      )->then( sub {
         my ( $first, $content ) = @_;

         log_if_fail "initial device query response", $content;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $federated_user_id );

         my $alice_keys = $device_keys->{ $federated_user_id };
         assert_json_keys( $alice_keys, ( $device_id1 ) );

         Future->needs_all(
            matrix_leave_room( $user, $room->room_id )->on_done( sub {
               log_if_fail "sent leave request";
            }),

            # make sure that the leave propagates back to the sytest server
            # see https://github.com/matrix-org/synapse/issues/8036
            $inbound_server->await_event(
               "m.room.member", $room->room_id, sub {
                  my ( $ev ) = @_;
                  log_if_fail "received event over federation", $ev;
                  return $ev->{state_key} eq $user->user_id &&
                     $ev->{content}{membership} eq 'leave';
               }
            ),
         );
      })->then( sub {
         log_if_fail "left room; now rejoining";
         my $iter = 0;
         retry_until_success {
            $iter++;
            matrix_join_room( $user, $room->room_id,
               server_name => $inbound_server->server_name,
            )->on_fail( sub {
               my ( $exc ) = @_;
               chomp $exc;
               log_if_fail "Room join iteration $iter failed: $exc";
            });
         }
      })->then( sub {
         log_if_fail "rejoined room";
         Future->needs_all(
            $inbound_server->await_request_user_devices( $federated_user_id )
            ->then( sub {
               my ( $req, undef ) = @_;
               assert_eq( $req->method, "GET", 'request method' );

               $req->respond_json( {
                  user_id   => $federated_user_id,
                  stream_id => 1,
                  devices   => [
                     {
                        device_id => $device_id1,
                        keys      => { device_keys => {} },
                     },
                     {
                        device_id => $device_id2,
                        keys      => { device_keys => {} },
                     },
                  ],
               } );
               Future->done(1);
            }),
            do_request_json_for( $user,
               method  => "POST",
               uri     => "/r0/keys/query",
               content => {
                  device_keys => {
                     $federated_user_id => [],
                  },
               },
            )->on_done( sub {
               log_if_fail "sent second device query request";
            }),
         );
      })->then( sub {
         my ( $first, $content ) = @_;

         log_if_fail "second query response", $content;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $federated_user_id );

         my $alice_keys = $device_keys->{ $federated_user_id };
         assert_json_keys( $alice_keys, ( $device_id1, $device_id2 ) );

         Future->done( 1 )
      });
   };

test "Local device key changes get to remote servers with correct prev_id",
   requires => [ local_user_fixtures( 2 ), $main::INBOUND_SERVER, federation_user_id_fixture(), room_alias_name_fixture() ],

   check => sub {
      my ( $user1, $user2, $inbound_server, $creator_id, $room_alias_name ) = @_;

      my $local_server_name = $inbound_server->server_name;
      my $datastore         = $inbound_server->datastore;

      my $room_alias = "#$room_alias_name:$local_server_name";

      my $prev_stream_id;

      $datastore->create_room(
         creator => $creator_id,
         alias   => $room_alias,
      );

      do_request_json_for( $user1,
         method => "POST",
         uri    => "/r0/join/$room_alias",

         content => {},
      )->then( sub {
         do_request_json_for( $user2,
            method => "POST",
            uri    => "/r0/join/$room_alias",

            content => {},
         )
      })->then( sub {
         Future->needs_all(
            $inbound_server->await_edu( "m.device_list_update", sub {1} )
            ->then( sub {
               my ( $edu ) = @_;
               log_if_fail "Received edu", $edu;

               assert_json_keys( $edu->{content}, qw( user_id device_id stream_id ) );
               assert_eq( $edu->{content}{user_id}, $user1->user_id );
               assert_eq( $edu->{content}{device_id}, $user1->device_id );

               $prev_stream_id = $edu->{content}{stream_id};

               Future->done(1);
            }),
            matrix_put_e2e_keys( $user1 )
         )
      })->then( sub {
         Future->needs_all(
            $inbound_server->await_edu( "m.device_list_update", sub {1} )
            ->then( sub {
               my ( $edu ) = @_;
               log_if_fail "Received edu", $edu;

               assert_json_keys( $edu->{content}, qw( user_id device_id stream_id prev_id ) );
               assert_eq( $edu->{content}{user_id}, $user2->user_id );
               assert_eq( $edu->{content}{device_id}, $user2->device_id );

               Future->done(1);
            }),
            matrix_put_e2e_keys( $user2 )
         )
      })->then( sub {
         Future->needs_all(
            $inbound_server->await_edu( "m.device_list_update", sub {1} )
            ->then( sub {
               my ( $edu ) = @_;
               log_if_fail "Received edu", $edu;

               assert_json_keys( $edu->{content}, qw( user_id device_id stream_id prev_id ) );
               assert_eq( $edu->{content}{user_id}, $user1->user_id );
               assert_eq( $edu->{content}{device_id}, $user1->device_id );
               assert_deeply_eq( $edu->{content}{prev_id}, [$prev_stream_id] );

               Future->done(1);
            }),
            matrix_put_e2e_keys( $user1, device_keys => { updated => "keys" } )
         )
      });
   };

use Data::Dumper;
test "Device list doesn't change if remote server is down",
   # see https://github.com/matrix-org/synapse/issues/5441

   requires => [
      $main::OUTBOUND_CLIENT,
      $main::INBOUND_SERVER,
      local_user_fixture,
      federation_user_id_fixture(),
      qw( can_upload_e2e_keys )
   ],

   check => sub {
      my (
         $outbound_client,
         $inbound_server,
         $local_user,
         $outbound_client_user
      ) = @_;

      my ( $first_keys_query_body, $second_keys_query_body, @respond_400 );

      my $client_user_devices = {
         user_id => $outbound_client_user,
         stream_id => 3,
         devices => [{
            device_id => "CURIOSITY_ROVER",
            keys => {
               user_id => $outbound_client_user,
               device_id => "CURIOSITY_ROVER",
               algorithms => ["fast", "and broken"],
               keys => {
                  "c" => "sharp",
                  "b" => "flat"
               },
               signatures => {
                  $outbound_client_user => {"ed25519:JLAFKJWSCS" => "dSO80A01XiigH3uBiDVx/EjzaoycHcjq9lfQX0uWsqxl2giMIiSPR8a4d291W1ihKJL/a+myXS367WT6NAIcBA"},
               },
            },
            device_display_name => "Curiosity Rover"
         }],
      };

      my $client_user_keys = {
         device_keys => {
            $outbound_client_user => {
               CURIOSITY_ROVER => {
                  user_id => $outbound_client_user,
                  device_id => "CURIOSITY_ROVER",
                  algorithms => ["fast", "and broken"],
                  keys => {
                     "c" => "sharp",
                     "b" => "flat"
                  },
                  signatures => {
                     $outbound_client_user => {"ed25519:JLAFKJWSCS" => "dSO80A01XiigH3uBiDVx/EjzaoycHcjq9lfQX0uWsqxl2giMIiSPR8a4d291W1ihKJL/a+myXS367WT6NAIcBA"}
                  },
                  unsigned => {
                     "device_display_name" => "Curiosity Rover"
                  },
               },
            },
         },
      };


      my @respond_with_keys = (
         $inbound_server->await_request_user_devices( $outbound_client_user )->then( sub {
            my ( $req ) = @_;
            $req->respond_json($client_user_devices);
            Future->done(1)
         }),
         $inbound_server->await_request_user_keys_query( $outbound_client_user )->then( sub {
            my ( $req ) = @_;
            $req->respond_json($client_user_keys);
            Future->done(1)
         })
      );

      # First we succesfully request the remote user's keys while the remote server is up.
      # We do this once they share a room.
      matrix_create_room(
         $local_user,
         preset => "public_chat",
      )->then( sub {
         my ( $room_id ) = @_;
         $outbound_client->join_room(
            server_name => $local_user->server_name,
            room_id     => $room_id,
            user_id     => $outbound_client_user,
         )
      })->then( sub {
         do_request_json_for( $local_user,
            method  => "POST",
            uri     => "/r0/keys/query",
            content => {
               device_keys => {
                  $outbound_client_user => []
               }
            }
         )
      })->then( sub {
         ( $first_keys_query_body ) = @_;
         map {$_->cancel} @respond_with_keys;
         log_if_fail (Dumper $first_keys_query_body);

         # We take the remote server 'offline' and then make the same request
         # for the users keys. We expect no change in the keys. We respond with
         # 400 instead of 503 to avoid the server being marked as down.
         @respond_400 = (
            $inbound_server->await_request_user_devices( $outbound_client_user )->then( sub {
               my ( $req ) = @_;
               log_if_fail "Responded with 400 to /user/devices request";
               $req->respond_json({}, code => 400);
               Future->done(1)
            }),
            $inbound_server->await_request_user_keys_query()->then( sub {
               my ( $req ) = @_;
               log_if_fail "Responded with 400 to /user/keys/query request";
               $req->respond_json({}, code => 400);
               Future->done(1)
            })
         );
         do_request_json_for( $local_user,
            method  => "POST",
            uri     => "/r0/keys/query",
            content => {
               device_keys => {
                  $outbound_client_user => []
               }
            }
         )
      })->then( sub {
         ( $second_keys_query_body ) = @_;
         map {$_->cancel} @respond_400;
         # The unsiged field is optional in the spec so we remove it from any response.
         foreach ($first_keys_query_body, $second_keys_query_body) {
            while (my ($user_key, $devices) = each %{$_->{ device_keys }} ) {
               while (my ($device_key, $values) = each %$devices) {
                  delete $values->{ unsigned };
               }
            }
         };

         log_if_fail (Dumper $second_keys_query_body);
         assert_deeply_eq( $second_keys_query_body->{ device_keys }, $first_keys_query_body->{ device_keys }, "Query matches while federation server is down." );
         Future->done(1)
      })
   };

# for https://github.com/matrix-org/synapse/issues/4827
use Data::Dumper;
test "If a device list update goes missing, the server resyncs on the next one",
   requires => [ local_user_fixture(),
                 $main::INBOUND_SERVER, $main::OUTBOUND_CLIENT,
                 federation_user_id_fixture(),
                 room_alias_name_fixture() ],

   check => sub {
      my ( $user, $inbound_server, $outbound_client, $creator_id, $room_alias_name ) = @_;

      my $local_server_name = $user->server_name;

      my $remote_server_name = $inbound_server->server_name;
      my $datastore          = $inbound_server->datastore;

      my $room_alias = "#$room_alias_name:$remote_server_name";

      my $device_id = "random_device_id";

      $datastore->create_room(
         creator => $creator_id,
         alias   => $room_alias,
      );

      my $client_keys = {
         user_id => $creator_id,
         device_id => $device_id,
         algorithms => ["m.olm.v1.curve25519-aes-sha2", "m.megolm.v1.aes-sha2"],
         # start off with no keys
         keys => {
         },
         signatures => {
         },
      };

      my $client_user_devices = {
         user_id => $creator_id,
         stream_id => 1,
         devices => [{
            device_id => $device_id,
            keys => $client_keys,
            device_display_name => "Original name"
         }],
      };

      my $client_user_keys = {
         device_keys => {
            $creator_id => {
               $device_id => $client_keys
            },
         },
      };

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

               $req->respond_json( $client_user_devices );

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
                     device_keys => $client_user_keys,
                  }
               }
            )
         )
      })->then( sub {
         # in stream_id 2, we add keys to the device but deliberately don't
         # tell the remote server about it.

         Future->needs_all(
            $inbound_server->await_request_user_devices( $creator_id )->then( sub {
               my ( $req ) = @_;
               log_if_fail "await_request_user_devices after out-of-order EDU";

               # add the missing keys from stream_id 2
               $client_keys->{ keys } = {
                  "curve25519:JJQDHPZKYD" => "MAtX5CLJXvHJ4wjvMBwc53+NnMceHiFch5r4mxOnOCA",
                  "ed25519:JJQDHPZKYD" => "LOu9tc6Sg7+mCEu3elrps3IiiotpefyaNnScTpSRQbU"
               };

               # then in stream_id 3, we rename the device
               # await a hit to federation/query, responding with stream ID 3
               $client_user_devices->{ stream_id } = 3;
               $client_user_devices->{ devices }->[0]->{ device_display_name } = "New device name";

               $req->respond_json($client_user_devices);
               Future->done(1)
            }),

            # deliberately send an out of order EDU to check that we get requeried
            $outbound_client->send_edu(
               edu_type    => "m.device_list_update",
               destination => $local_server_name,
               content     => {
                  user_id             => $creator_id,
                  device_id           => $device_id,
                  device_display_name => "New device name",
                  # deliberately skip an EDU in sequence to check
                  # that we get re-queried
                  prev_id             => [ 2 ],
                  stream_id           => 3,

                  keys => {
                     device_keys => $client_user_keys
                  }
               }
            )
         );
      })->then( sub {
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/keys/query",
            content => {
               device_keys => {
                  $creator_id => [ $device_id ],
               }
            }
         )
      })->then( sub {
         my ( $content ) = @_;

         log_if_fail "query response", $content;

         assert_json_keys( $content, "device_keys" );

         my $device_keys = $content->{device_keys};
         assert_json_keys( $device_keys, $creator_id );

         my $creator_keys = $device_keys->{ $creator_id };
         assert_json_keys( $creator_keys, $device_id );

         my $creator_device_keys = $creator_keys->{ $device_id };
         assert_json_keys( $creator_device_keys, "unsigned" );

         my $unsigned = $creator_device_keys->{unsigned};

         # check the keys are there from stream id 2
         assert_json_keys( $creator_device_keys->{keys}, "curve25519:JJQDHPZKYD");
         assert_json_keys( $creator_device_keys->{keys}, "ed25519:JJQDHPZKYD");

         # check the name is there from stream id 3
         assert_eq( $unsigned->{device_display_name}, "New device name" );

         Future->done( 1 )
      });
   };

# for https://github.com/matrix-org/synapse/issues/6399
# test "When a room is upgraded to E2E, device lists caches should be flushed"
# in practice, if you share a room with a user, your device list should be synced
# irrespective of E2E, so let's not bother testing this now

# for https://github.com/matrix-org/synapse/issues/6399
#
# If you see you have a room in common with a user, you blindly assume you
# have been receiving device_list updates for them.  But this fails if there
# was some period where you didn't have a room in common (or if an EDU got dropped).
# So instead, we should either flush the devicelist cache when we stop sharing a room
# with a user, or flush it when we start sharing a room.
#
# test "Device lists caches should be flushed when you re-encounter a user"

# test "Device lists get refreshed when you encounter an unrecognised device" # for https://github.com/matrix-org/synapse/issues/5095#issuecomment-501512352
# however, this doesn't help us if the keys just change

# test "If you send >20 device lists updates in a row, they don't get lost?" # for https://github.com/matrix-org/synapse/issues/5153
