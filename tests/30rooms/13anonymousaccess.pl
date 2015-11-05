test "Anonymous user cannot view non-world-readable rooms",
   requires => [ qw( first_api_client ), local_user_preparer() ],

   do => sub {
      my ( $api_client, $user ) = @_;

      my $anonymous_user;
      my $room_id;

      register_anonymous_user( $api_client )->then( sub {
         ( $anonymous_user ) = @_;

         matrix_create_and_join_room( [ $user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_set_room_history_visibility( $user, $room_id, "shared" );
         })->then( sub {
            matrix_send_room_text_message( $user, $room_id, body => "mice" )
         })->then( sub {
            do_request_json_for( $anonymous_user,
               method => "GET",
               uri    => "/api/v1/rooms/$room_id/messages",
               params => {
                  limit => "1",
                  dir   => "b",
               },
            )
         })->main::expect_http_403;
      });
   };

test "Anonymous user can view world-readable rooms",
   requires => [ qw( first_api_client ), local_user_preparer() ],

   do => sub {
      my ( $api_client, $user ) = @_;

      my $anonymous_user;
      my $room_id;

      register_anonymous_user( $api_client )->then( sub {
         ( $anonymous_user ) = @_;

         matrix_create_and_join_room( [ $user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
         })->then( sub {
            matrix_send_room_text_message( $user, $room_id, body => "mice" )
         })->then( sub {
            do_request_json_for( $anonymous_user,
               method => "GET",
               uri    => "/api/v1/rooms/$room_id/messages",
               params => {
                  limit => "2",
                  dir   => "b",
               },
            )
         });
      });
   };

test "Anonymous user cannot call /events on non-world_readable room",
   requires => [ qw( first_api_client ), local_user_preparer() ],

   do => sub {
      my ( $api_client, $user ) = @_;

      my $anonymous_user;
      my $room_id;

      register_anonymous_user( $api_client )->then( sub {
         ( $anonymous_user ) = @_;

         matrix_create_and_join_room( [ $user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_send_room_text_message( $user, $room_id, body => "mice" )
         })->then( sub {
            do_request_json_for( $anonymous_user,
               method => "GET",
               uri    => "/api/v1/rooms/${room_id}/messages",
               params => {
                  limit => "2",
                  dir   => "b",
               },
            )
         })->main::expect_http_403;
      });
   };

test "Anonymous user can call /events on world_readable room",
   requires => [ qw( first_api_client ), local_user_preparer() ],

   do => sub {
      my ( $api_client, $user ) = @_;

      my $anonymous_user;
      my $room_id;

      register_anonymous_user( $api_client )->then( sub {
         ( $anonymous_user ) = @_;

         matrix_create_and_join_room( [ $user ] )
         ->then( sub {
            ( $room_id ) = @_;

            matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
         })->then( sub {
            Future->needs_all(
               delay( 0.05 )->then( sub {
                  matrix_send_room_text_message( $user, $room_id, body => "mice" );
               }),

               do_request_json_for( $anonymous_user,
                  method => "GET",
                  uri    => "/api/v1/events",
                  params => {
                     limit => "2",
                     dir   => "b",
                  },
               )->main::expect_http_400->then( sub {
                  do_request_json_for( $anonymous_user,
                     method => "GET",
                     uri    => "/api/v1/events",
                     params => {
                        limit   => "2",
                        dir     => "b",
                        room_id => $room_id,
                     },
                  )
               })->then( sub {
                  my ( $body ) = @_;

                  require_json_keys( $body, qw( chunk ) );
                  $body->{chunk} >= 1 or die "Want at least one event";
                  my $event = $body->{chunk}[0];
                  require_json_keys( $event, qw( content ) );
                  my $content = $event->{content};
                  require_json_keys( $content, qw( body ) );
                  $content->{body} eq "mice" or die "Want content body to be mice";

                  Future->done( 1 );
               }),
            );
         });
      });
   };

test "Anonymous user doesn't get events before room made world_readable",
   requires => [ qw( first_api_client ), local_user_preparer() ],

   do => sub {
      my ( $api_client, $user ) = @_;

      my $anonymous_user;
      my $room_id;

      register_anonymous_user( $api_client )->then( sub {
         ( $anonymous_user ) = @_;

         matrix_create_and_join_room( [ $user ] )
         ->then( sub {
            ( $room_id ) = @_;

            Future->needs_all(
               delay( 0.05 )->then( sub {
                  matrix_send_room_text_message( $user, $room_id, body => "private" )->then(sub {
                     matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
                  })->then( sub {
                     matrix_send_room_text_message( $user, $room_id, body => "public" );
                  });
               }),

               # The client is allowed to see exactly two events, the
               # m.room.history_visibility event and the public message.
               # The server is free to return these in separate calls to
               # /events, so we try at most two times to get the events we expect.
               check_events( $anonymous_user, $room_id )
               ->then(sub {
                  Future->done( 1 );
               }, sub {
                  check_events( $anonymous_user, $room_id );
               }),
            );
         });
      });
   };

test "Anonymous users can get state for non-world_readable rooms",
   requires => [ local_user_and_room_preparers(), qw( first_api_client ) ],

   check => sub {
      my ( $user, $room_id, $api_client ) = @_;

      register_anonymous_user( $api_client )->then( sub {
         my ( $anonymous_user ) = @_;

         do_request_json_for( $anonymous_user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state",
         )
      })
   },

   do => sub {
      my ( $user, $room_id ) = @_;

      matrix_set_room_history_visibility( $user, $room_id, "world_readable" );
   };

test "Anonymous users can get individual state for world_readable rooms",
   requires => [ local_user_and_room_preparers(), qw( first_api_client ) ],

   check => sub {
      my ( $user, $room_id, $api_client ) = @_;

      register_anonymous_user( $api_client )->then( sub {
         my ( $anonymous_user ) = @_;

         do_request_json_for( $anonymous_user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state/m.room.member/".$user->user_id,
         )
      })
   },

   do => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method  => "PUT",
         uri     => "/api/v1/rooms/$room_id/state/m.room.history_visibility/",

         content => {
            history_visibility => "world_readable",
         },
      );
   };


sub check_events
{
   my ( $user, $room_id ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/api/v1/events",
      params => {
         limit   => "3",
         dir     => "b",
         room_id => $room_id,
      },
   )->then( sub {
      my ( $body ) = @_;

      log_if_fail "Body", $body;

      require_json_keys( $body, qw( chunk ) );
      @{$body->{chunk}} >= 1 or die "Want at least one event";
      @{$body->{chunk}} < 3 or die "Want at most two events";

      my $found = 0;
      foreach my $event ($body->{chunk}) {
         next if all { $_ ne "content" } keys $event;
         next if all { $_ ne "body" } keys $event->{content};
         $found = 1 if $event->{content}->{body} eq "public";
         die "Should not have found private" if $event->{content}->{body} eq "private";
      }

      Future->done( $found );
   }),
}

sub register_anonymous_user
{
   my ( $http ) = @_;

   $http->do_request_json(
      method  => "POST",
      uri     => "/v2_alpha/register",
      content => {},
      params  => {
         kind => "guest",
      },
   )->then( sub {
      my ( $body ) = @_;
      my $access_token = $body->{access_token};

      Future->done( User( $http, $body->{user_id}, $access_token, undef, undef, [], undef ) );
   });
}

push our @EXPORT, qw( matrix_set_room_history_visibility );

sub matrix_set_room_history_visibility
{
   my ( $user, $room_id, $history_visibility ) = @_;

   matrix_put_room_state( $user, $room_id,
      type    => "m.room.history_visibility",
      content => { history_visibility => $history_visibility }
   );
}
