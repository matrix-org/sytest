use List::Util qw( first );
use Future::Utils qw( repeat );

# test "Guest user cannot call /events globally",
#    requires => [ guest_user_fixture() ],
#
#    do => sub {
#       my ( $guest_user ) = @_;
#
#       matrix_get_events( $guest_user )
#          ->followed_by( \&expect_4xx_or_empty_chunk );
#    };
#
# test "Guest users can join guest_access rooms",
#    requires => [ local_user_and_room_fixtures(), guest_user_fixture() ],
#
#    do => sub {
#       my ( $user, $room_id ) = @_;
#
#       matrix_set_room_guest_access( $user, $room_id, "can_join" );
#    },
#
#    check => sub {
#       my ( undef, $room_id, $guest_user ) = @_;
#
#       matrix_join_room( $guest_user, $room_id );
#    };
#
# test "Guest users can send messages to guest_access rooms if joined",
#    requires => [ local_user_and_room_fixtures(), guest_user_fixture() ],
#
#    do => sub {
#       my ( $user, $room_id, $guest_user ) = @_;
#
#       matrix_set_room_guest_access( $user, $room_id, "can_join" )
#       ->then( sub {
#          matrix_join_room( $guest_user, $room_id )
#       })->then( sub {
#          matrix_send_room_text_message( $guest_user, $room_id, body => "sup" );
#       })->then( sub {
#          # We need to repeatedly call /messages as it may take some time before
#          # the message propogates through the system.
#          retry_until_success {
#             matrix_get_room_messages( $user, $room_id, limit => 1 )
#             ->then( sub {
#                my ( $body ) = @_;
#                log_if_fail "Body:", $body;
#
#                assert_json_keys( $body, qw( chunk ));
#                assert_json_list( my $chunk = $body->{chunk} );
#
#                scalar @$chunk == 1 or
#                   die "Expected one message";
#
#                my ( $event ) = @$chunk;
#
#                assert_json_keys( $event, qw( type room_id user_id content ));
#
#                $event->{user_id} eq $guest_user->user_id or
#                   die "expected user_id to be ".$guest_user->user_id;
#
#                $event->{content}->{body} eq "sup" or
#                   die "content to be sup";
#
#                Future->done(1);
#             })
#          }
#       });
#    };
#
# test "Guest user calling /events doesn't tightloop",
#    requires => [ guest_user_fixture(), local_user_fixture() ],
#
#    do => sub {
#       my ( $guest_user, $user ) = @_;
#
#       my ( $room_id );
#
#       matrix_create_and_join_room( [ $user ] )
#       ->then( sub {
#          ( $room_id ) = @_;
#
#          matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
#       })->then( sub {
#          do_request_json_for( $guest_user,
#             method => "GET",
#             uri    => "/r0/rooms/$room_id/initialSync",
#          );
#       })->then( sub {
#          my ( $sync_body ) = @_;
#          my $sync_from = $sync_body->{messages}->{end};
#
#          repeat( sub {
#             my ( undef, $f ) = @_;
#
#             my $end_token = $f ? $f->get->{end} : $sync_from;
#
#             log_if_fail "Events body", $f ? $f->get : undef;
#
#             matrix_get_events( $guest_user,
#                room_id => $room_id,
#                timeout => 0,
#                from    => $end_token,
#             );
#          }, foreach => [ 0 .. 5 ], until => sub {
#             my ( $res ) = @_;
#             $res->failure or not @{ $res->get->{chunk} };
#          });
#       })->then( sub {
#           my ( $body ) = @_;
#
#          log_if_fail "Body", $body;
#
#          assert_json_empty_list( $body->{chunk} );
#
#          Future->done(1);
#       });
#    };
#
# test "Guest users are kicked from guest_access rooms on revocation of guest_access",
#    requires => [ local_user_and_room_fixtures(), guest_user_fixture() ],
#
#    do => sub {
#       my ( $user, $room_id, $guest_user ) = @_;
#
#       matrix_set_room_guest_access( $user, $room_id, "can_join" )
#       ->then( sub {
#          matrix_join_room( $guest_user, $room_id );
#       })->then( sub {
#          matrix_get_room_membership( $user, $room_id, $guest_user );
#       })->then( sub {
#          my ( $membership ) = @_;
#
#          assert_eq( $membership, "join", "membership" );
#
#          matrix_set_room_guest_access( $user, $room_id, "forbidden" );
#       })->then( sub {
#          matrix_get_room_membership( $user, $room_id, $guest_user );
#       })->then( sub {
#          my ( $membership ) = @_;
#
#          assert_eq( $membership, "leave", "membership" );
#
#          Future->done( 1 );
#       });
#    };

test "Guest user can set display names",
   requires => [ guest_user_fixture(), local_user_and_room_fixtures() ],

   do => sub {
      my ( $guest_user, $user, $room_id ) = @_;

      my $displayname_uri = "/r0/profile/:user_id/displayname";

      matrix_set_room_guest_access( $user, $room_id, "can_join" )->then( sub {
         matrix_join_room( $guest_user, $room_id );
      })->then( sub {
         do_request_json_for( $guest_user,
            method => "GET",
            uri    => $displayname_uri,
      )})->then( sub {
         my ( $body ) = @_;

         # We used to assert here that the initial displayname was undefined, but as
         # we let homeservers set sensible defaults these days, it's been relaxed.

         do_request_json_for( $guest_user,
            method  => "PUT",
            uri     => $displayname_uri,
            content => {
               displayname => "creeper",
            },
      )})->then( sub {
         retry_until_success {
            Future->needs_all(
               do_request_json_for( $guest_user,
                  method => "GET",
                  uri    => $displayname_uri,
               )->then( sub {
                  my ( $body ) = @_;
                  assert_eq( $body->{displayname}, "creeper", "Profile displayname" );

                  Future->done(1);
               }),
               do_request_json_for( $guest_user,
                  method => "GET",
                  uri    => "/r0/rooms/$room_id/state/m.room.member/:user_id",
               )->then( sub {
                  my ( $body ) = @_;
                  assert_eq( $body->{displayname}, "creeper", "Room displayname" );

                  Future->done(1);
               }),
            );
         }
      });
   };

# test "Guest users are kicked from guest_access rooms on revocation of guest_access over federation",
#    requires => [ local_user_fixture(), remote_user_fixture(), guest_user_fixture() ],
#
#    do => sub {
#       my ( $local_user, $remote_user, $guest_user ) = @_;
#
#       my $room_id;
#
#       matrix_create_and_join_room( [ $local_user, $remote_user ] )
#       ->then( sub {
#          ( $room_id ) = @_;
#
#          matrix_change_room_power_levels( $local_user, $room_id, sub {
#             my ( $levels ) = @_;
#             $levels->{users}{ $remote_user->user_id } = 50;
#          })->then( sub {
#             matrix_set_room_guest_access( $local_user, $room_id, "can_join" )
#          })->then( sub {
#             matrix_join_room( $remote_user, $room_id );
#          })->then( sub {
#             matrix_join_room( $guest_user, $room_id );
#          })->then( sub {
#             matrix_get_room_membership( $local_user, $room_id, $guest_user );
#          })->then( sub {
#             my ( $membership ) = @_;
#
#             assert_eq( $membership, "join", "membership" );
#
#             Future->needs_all(
#                await_event_for( $local_user, filter => sub {
#                   my ( $event ) = @_;
#                   return $event->{type} eq "m.room.guest_access" && $event->{content}->{guest_access} eq "forbidden";
#                }),
#
#                # This may fail a few times if the power level event hasn't federated yet.
#                # So we retry.
#                retry_until_success {
#                   matrix_set_room_guest_access( $remote_user, $room_id, "forbidden" );
#                },
#             );
#          })->then( sub {
#             repeat_until_true {
#                matrix_get_room_membership( $local_user, $room_id, $guest_user )
#                ->then( sub {
#                   my ( $membership ) = @_;
#                   Future->done( $membership eq "leave" );
#                })
#             };
#          });
#       })
#    };
#
# test "Guest user can upgrade to fully featured user",
#    requires => [ local_user_and_room_fixtures(), guest_user_fixture(), $main::API_CLIENTS[0] ],
#
#    do => sub {
#       my ( $creator, $room_id, $guest_user, $http ) = @_;
#
#       my ( $local_part ) = $guest_user->user_id =~ m/^@([^:]+):/g;
#       $http->do_request_json(
#          method  => "POST",
#          uri     => "/r0/register",
#          content => {
#             username => $local_part,
#             password => "SIR_Arthur_David",
#             guest_access_token => $guest_user->access_token,
#          },
#       )->followed_by( sub {
#          $http->do_request_json(
#             method  => "POST",
#             uri     => "/r0/register",
#             content => {
#                username     => $local_part,
#                password     => "SIR_Arthur_David",
#                guest_access_token => $guest_user->access_token,
#                auth         => {
#                   type => "m.login.dummy",
#                },
#             },
#          )
#       })->on_done( sub {
#          my ( $body ) = @_;
#          $guest_user->access_token = $body->{access_token};
#       })
#    },
#
#    check => sub {
#       my ( undef, $room_id, $guest_user ) = @_;
#
#       matrix_join_room( $guest_user, $room_id );
#    };
#
# test "Guest user cannot upgrade other users",
#    requires => [ local_user_and_room_fixtures(), guest_user_fixture(), guest_user_fixture(), $main::API_CLIENTS[0] ],
#
#    do => sub {
#       my ( $creator, $room_id, $guest_user1, $guest_user2, $http ) = @_;
#
#       my ( $local_part1 ) = $guest_user1->user_id =~ m/^@([^:]+):/g;
#       $http->do_request_json(
#          method  => "POST",
#          uri     => "/r0/register",
#          content => {
#             username => $local_part1,
#             password => "SIR_Arthur_David",
#             guest_access_token => $guest_user2->access_token,
#          },
#       )->main::expect_http_4xx;
#    };
#
#
# test "GET /publicRooms lists rooms",
#    requires => [ $main::API_CLIENTS[0], local_user_fixture() ],
#
#    check => sub {
#       my ( $http, $user ) = @_;
#
#       my %rooms = (
#          listingtest0 => {},
#          listingtest1 => { history_visibility => "world_readable" },
#          listingtest2 => { history_visibility => "invited" },
#          listingtest3 => { guest_access => "can_join" },
#          listingtest4 => { guest_access => "can_join", history_visibility => "world_readable" },
#       );
#
#       Future->needs_all( map {
#          my $aliasname = $_;
#          my $settings = $rooms{$_};
#          my $room_id;
#
#          my $f = matrix_create_room( $user,
#             visibility => "public",
#             room_alias_name => $aliasname,
#          )->on_done( sub {
#             ( $room_id, undef ) = ( @_ );
#          });
#
#          if( $settings->{guest_access} ) {
#             $f = $f->then( sub {
#                matrix_set_room_guest_access( $user, $room_id, $settings->{guest_access} );
#             });
#          }
#
#          if( $settings->{history_visibility} ) {
#             $f = $f->then( sub {
#                matrix_set_room_history_visibility( $user, $room_id, $settings->{history_visibility} );
#             });
#          }
#
#          $f->on_done( sub {
#             log_if_fail "Created room $room_id for alias $aliasname with settings:", $settings;
#          });
#       } keys %rooms )->then( sub {
#          my $iter = 0;
#          retry_until_success {
#             $iter++;
#             $http->do_request_json(
#                method => "GET",
#                uri    => "/r0/publicRooms",
#             )->then( sub {
#                my ( $body ) = @_;
#
#                log_if_fail "Iteration $iter: publicRooms result", $body;
#
#                assert_json_keys( $body, qw( chunk ));
#                assert_json_list( $body->{chunk} );
#
#                my %isOK = map { $_ => 0 } keys %rooms;
#
#                foreach my $room ( @{ $body->{chunk} } ) {
#                   my $canonical_alias = $room->{canonical_alias};
#                   assert_json_boolean( my $world_readable = $room->{world_readable} );
#                   assert_json_boolean( my $guest_can_join = $room->{guest_can_join} );
#
#                   my $alias_local = first { $canonical_alias =~ m/^#$_:/ } keys %rooms;
#                   next unless $alias_local;
#                   my $settings = $rooms{$alias_local};
#
#                   if(( $settings->{history_visibility} // "" ) eq "world_readable" ) {
#                      $world_readable or die "Expected $alias_local to be world_readable";
#                   } else {
#                      $world_readable and die "Expected $alias_local not to be world_readable";
#                   }
#
#                   if(( $settings->{guest_access} // "" ) eq "can_join" ) {
#                      $guest_can_join or die "Expected $alias_local to be guest-joinable";
#                   } else {
#                      $guest_can_join and die "Expected $alias_local not to be guest-joinable";
#                   }
#
#                   $isOK{$alias_local} = 1;
#                }
#
#                foreach my $alias ( keys %rooms ) {
#                   $isOK{$alias} or die "$alias not found in result";
#                }
#
#                Future->done( 1 );
#             })->on_fail( sub {
#                my ( $exc ) = @_;
#                chomp $exc;
#                log_if_fail "Iteration $iter: not ready yet: $exc";
#             });
#          };
#       })
#    };
#
# test "GET /publicRooms includes avatar URLs",
#    requires => [ $main::API_CLIENTS[0], local_user_fixture() ],
#
#    check => sub {
#       my ( $http, $user ) = @_;
#
#       Future->needs_all(
#          matrix_create_room( $user,
#             visibility => "public",
#             room_alias_name => "nonworldreadable",
#          )->then( sub {
#             my ( $room_id ) = @_;
#
#             matrix_put_room_state( $user, $room_id,
#                type      => "m.room.avatar",
#                state_key => "",
#                content   => {
#                   url => "https://example.com/ruffed.jpg",
#                }
#             );
#          }),
#
#          matrix_create_room( $user,
#             visibility => "public",
#             room_alias_name => "worldreadable",
#          )->then( sub {
#             my ( $room_id ) = @_;
#
#             Future->needs_all(
#                matrix_set_room_history_visibility( $user, $room_id, "world_readable" ),
#                matrix_put_room_state( $user, $room_id,
#                   type      => "m.room.avatar",
#                   state_key => "",
#                   content   => {
#                      url => "https://example.com/ringtails.jpg",
#                   }
#                ),
#             );
#          }),
#       )->then( sub {
#          repeat_until_true {
#             $http->do_request_json(
#                method => "GET",
#                uri    => "/r0/publicRooms",
#             )->then( sub {
#                my ( $body ) = @_;
#
#                log_if_fail "publicRooms", $body;
#
#                assert_json_keys( $body, qw( chunk ));
#                assert_json_list( $body->{chunk} );
#
#                my %isOK = (
#                   worldreadable    => 0,
#                   nonworldreadable => 0,
#                );
#
#                foreach my $room ( @{ $body->{chunk} } ) {
#                   my $canonical_alias = $room->{canonical_alias};
#
#                   if( $canonical_alias =~ m/^\Q#worldreadable:/ ) {
#                      $isOK{worldreadable} =
#                         ( $room->{avatar_url} eq "https://example.com/ringtails.jpg" );
#                   }
#                   elsif( $canonical_alias =~ m/^\Q#nonworldreadable:/ ) {
#                      $isOK{nonworldreadable} =
#                         ( $room->{avatar_url} eq "https://example.com/ruffed.jpg" );
#                   }
#                }
#
#                Future->done( all { $isOK{$_} } keys %isOK );
#             });
#          };
#       });
#    };
#
# test "Guest users can accept invites to private rooms over federation",
#    requires => [ remote_user_fixture(), guest_user_fixture() ],
#
#    do => sub {
#       my ( $remote_user, $local_guest ) = @_;
#
#       my ( $room_id );
#
#       matrix_create_room( $remote_user )->then( sub {
#          ( $room_id ) = @_;
#
#          matrix_put_room_state( $remote_user, $room_id,
#             type      => "m.room.join_rules",
#             state_key => "",
#             content   => {
#                join_rule => "invite",
#             }
#          )
#       })->then( sub {
#          matrix_set_room_guest_access( $remote_user, $room_id, "can_join" )
#       })->then( sub {
#          matrix_invite_user_to_room( $remote_user, $local_guest, $room_id )
#       })->then( sub {
#          matrix_join_room( $local_guest, $room_id );
#       })->then( sub {
#          Future->done( 1 );
#       });
#    };
#
# test "Guest users denied access over federation if guest access prohibited",
#    requires => [ remote_user_fixture(), guest_user_fixture() ],
#
#    do => sub {
#       my ( $remote_user, $local_guest ) = @_;
#
#       my ( $room_id );
#
#       matrix_create_room( $remote_user )->then( sub {
#          ( $room_id ) = @_;
#
#          matrix_put_room_state( $remote_user, $room_id,
#             type      => "m.room.join_rules",
#             state_key => "",
#             content   => {
#                join_rule => "invite",
#             }
#          )
#       })->then( sub {
#          matrix_set_room_guest_access( $remote_user, $room_id, "forbidden" )
#       })->then( sub {
#          matrix_invite_user_to_room( $remote_user, $local_guest, $room_id )
#       })->then( sub {
#          matrix_join_room( $local_guest, $room_id )
#          ->main::expect_http_403
#       })->then( sub {
#          Future->done( 1 );
#       });
#    };

push our @EXPORT, qw( guest_user_fixture );

sub guest_user_fixture
{
   fixture(
      requires => [ $main::API_CLIENTS[0] ],

      setup => sub {
         my ( $http ) = @_;

         $http->do_request_json(
            method  => "POST",
            uri     => "/r0/register",
            content => {},
            params  => {
               kind => "guest",
            },
         )->then( sub {
            my ( $body ) = @_;
            my $access_token = $body->{access_token};

            Future->done( new_User(
               http         => $http,
               user_id      => $body->{user_id},
               device_id    => $body->{device_id},
               access_token => $access_token,
            ));
         });
   })
}

push @EXPORT, qw( matrix_set_room_guest_access matrix_set_room_guest_access_synced );

sub matrix_set_room_guest_access
{
   my ( $user, $room_id, $guest_access ) = @_;

   matrix_put_room_state( $user, $room_id,
      type    => "m.room.guest_access",
      content => { guest_access => $guest_access }
   );
}

sub matrix_set_room_guest_access_synced
{
   my ( $user, $room_id, $guest_access ) = @_;

   matrix_put_room_state_synced( $user, $room_id,
      type    => "m.room.guest_access",
      content => { guest_access => $guest_access }
   );
}

push @EXPORT, qw( matrix_get_room_membership );

sub matrix_get_room_membership
{
   my ( $checking_user, $room_id, $tested_user ) = @_;

   matrix_get_room_state( $checking_user, $room_id,
      type => "m.room.member",
      state_key => $tested_user->user_id,
   )->then(
      sub {
         my ( $content ) = @_;

         Future->done( $content->{membership} );
      },
      sub {
         Future->done( "leave" );
      }
   );
}


push @EXPORT, qw( matrix_set_room_history_visibility matrix_set_room_history_visibility_synced );

sub matrix_set_room_history_visibility
{
   my ( $user, $room_id, $history_visibility ) = @_;

   if ( $history_visibility eq 'default') {
       return Future->done();
   }

   matrix_put_room_state( $user, $room_id,
      type    => "m.room.history_visibility",
      content => { history_visibility => $history_visibility }
   );
}

sub matrix_set_room_history_visibility_synced
{
   my ( $user, $room_id, $history_visibility ) = @_;

   if ( $history_visibility eq 'default') {
       return Future->done();
   }

   matrix_put_room_state_synced( $user, $room_id,
      type    => "m.room.history_visibility",
      content => { history_visibility => $history_visibility }
   );
}

push @EXPORT, qw( expect_4xx_or_empty_chunk);

sub expect_4xx_or_empty_chunk
{
   my ( $f ) = @_;

   $f->then( sub {
      my ( $body ) = @_;

      log_if_fail "Body", $body;

      assert_json_keys( $body, qw( chunk ) );
      assert_json_list( $body->{chunk} );
      die "Want list to be empty" if @{ $body->{chunk} };

      Future->done(1);
   },
   http => sub {
      my ( undef, undef, $response ) = @_;

      log_if_fail "HTTP Response", $response;

      $response->code >= 400 and $response->code < 500 or die "want 4xx";

      Future->done(1);
   });
}
