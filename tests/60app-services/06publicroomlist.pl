use Future::Utils qw( try_repeat_until_success );


use constant AS_PREFIX => "/_matrix/app/unstable";


sub get_room_list_synced
{
   my ( $user, %opts ) = @_;

   my $content = $opts{content};

   $content->{limit} //= 100000000;

   my $check = $opts{check};

   try_repeat_until_success( sub {
      do_request_json_for( $user,
         method => "POST",
         uri    => "/r0/publicRooms",

         content => $content,
      )->then( sub {
         Future->done( $check->( @_ ) )
      })
   });
}


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
         get_room_list_synced( $local_user,
            content => {},

            check => sub {
               my ( $body ) = @_;

               any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
                  and die "AS public room in main list";
            },
         )
      })->then( sub {
         log_if_fail "AS public room not in main list";

         get_room_list_synced( $local_user,
            content => { third_party_instance_id => $instance_id },

            check => sub {
               my ( $body ) = @_;

               any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
                  or die "AS public room is not in the AS list";
            },
         )
      })->then( sub {
         log_if_fail "AS public room in AS list";

         get_room_list_synced( $local_user,
            content => { include_all_networks => "true" },

            check => sub {
               my ( $body ) = @_;

               any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
                  or die "AS public room is not in the full room list";
            },
         )
      })->then( sub {
         log_if_fail "AS public room in full list";

         do_request_json_for( $as_user,
            method => "DELETE",
            uri    => "/r0/directory/list/appservice/$network_id/$room_id",
         )
      })->then( sub {
         get_room_list_synced( $local_user,
            content => { third_party_instance_id => $instance_id },

            check => sub {
               my ( $body ) = @_;

               any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
                  and die "AS public room in AS list after deletion";
            },
         )
      });
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
         get_room_list_synced( $local_user,
            content => {},

            check => sub {
               my ( $body ) = @_;

               any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
                  or die "Room not in main list";
            },
         )
      })->then( sub {
         log_if_fail "Room in main list";

         get_room_list_synced( $local_user,
            content => { third_party_instance_id => $instance_id },

            check => sub {
               my ( $body ) = @_;

               any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
                  or die "Room is not in the AS list";
            },
         )
      })->then( sub {
         log_if_fail "Room in AS list";

         do_request_json_for( $local_user,
            method => "POST",
            uri    => "/r0/publicRooms",

            content => { include_all_networks => "true", limit => 1000000 }
         )
      })->then( sub {
         do_request_json_for( $as_user,
            method => "DELETE",
            uri    => "/r0/directory/list/appservice/$network_id/$room_id",
         )
      })->then( sub {
         get_room_list_synced( $local_user,
            content => { third_party_instance_id => $instance_id },

            check => sub {
               my ( $body ) = @_;

               any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
                  and die "Room in AS list after deletion";
            },
         )
      })->then( sub {
         log_if_fail "Room not in AS list after deletion";

         get_room_list_synced( $local_user,
            content => {},

            check => sub {
               my ( $body ) = @_;

               any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
                  or die "Room not in main list after AS list deletion";
            },
         )
      })->then( sub {
         log_if_fail "Room in main list after deletion";

         get_room_list_synced( $local_user,
            content => { include_all_networks => "true" },

            check => sub {
               my ( $body ) = @_;

               any { $room_id eq $_->{room_id} } @{ $body->{chunk} }
                  or die "Room is not in the full room list after AS deletion";
            },
         )
      })
   };
