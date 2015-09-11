use List::Util qw( first );
use Data::Dumper;

test "A room can be created set to invite-only",
   requires => [qw( do_request_json can_create_room )],

   provides => [qw( inviteonly_room_id )],

   do => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "POST",
         uri    => "/api/v1/createRoom",

         content => {
            # visibility: "private" actually means join_rule: "invite"
            # See SPEC-74
            visibility => "private",
         },
      )->then( sub {
         my ( $body ) = @_;

         my $room_id = $body->{room_id};

         $do_request_json->(
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/initialSync",
         )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( state ));

            my ( $join_rules_event ) = first { $_->{type} eq "m.room.join_rules" } @{ $body->{state} };
            $join_rules_event or
               die "Failed to find an m.room.join_rules event";

            $join_rules_event->{content}{join_rule} eq "invite" or
               die "Expected join rule to be 'invite'";

            provide inviteonly_room_id => $room_id;

            Future->done(1);
         });
      });
   };

test "Uninvited users cannot join the room",
   requires => [qw( do_request_json_for more_users inviteonly_room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $uninvited = $more_users->[0];

      $do_request_json_for->( $uninvited,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/join",

         content => {},
      )->then(
         sub { # done
            Future->fail( "Expected not to succeed to join the room" );
         },
         sub { # fail
            my ( $failure, $name, @args ) = @_;

            defined $name and $name eq "http" or
               die "Expected failure kind to be 'http'";

            my ( $resp, $req ) = @args;
            $resp->code == 403 or
               die "Expected HTTP response code to be 403";

            # TODO: Check the response content a bit?

            Future->done(1);
         },
      );
   };

test "Can invite users to invite-only rooms",
   requires => [qw( do_request_json more_users inviteonly_room_id
                    can_invite_room )],

   do => sub {
      my ( $do_request_json, $more_users, $room_id ) = @_;
      my $invitee = $more_users->[1];

      $do_request_json->(
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/invite",

         content => { user_id => $invitee->user_id },
      );
   };

test "Invited user receives invite",
   requires => [qw( await_event_for more_users inviteonly_room_id
                    can_invite_room )],

   await => sub {
      my ( $await_event_for, $more_users, $room_id ) = @_;
      my $invitee = $more_users->[1];

      $await_event_for->( $invitee, sub {
         my ( $event ) = @_;

         require_json_keys( $event, qw( type ));
         return 0 unless $event->{type} eq "m.room.member";

         require_json_keys( $event, qw( room_id state_key ));
         return 0 unless $event->{room_id} eq $room_id;
         return 0 unless $event->{state_key} eq $invitee->user_id;

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "invite" or
            die "Expected membership to be 'invite'";

         return 1;
      });
   };

test "Invited user can join the room",
   requires => [qw( do_request_json_for more_users inviteonly_room_id
                    can_invite_room can_join_room_by_id )],

   do => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;
      my $invitee = $more_users->[1];

      $do_request_json_for->( $invitee,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/join",

         content => {},
      )->then( sub {
         $do_request_json_for->( $invitee,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state/m.room.member/${\$invitee->user_id}",
         )
      })->then( sub {
         my ( $member_state ) = @_;

         $member_state->{membership} eq "join" or
            die "Expected my membership to be 'join'";

         Future->done(1);
      });
   };

test "Banned user is kicked and may not rejoin",
   requires => [qw( do_request_json_for user more_users room_id
                    can_ban_room )],

   do => sub {
      my ( $do_request_json_for, $user, $more_users, $room_id ) = @_;
      my $banned_user = $more_users->[0];

      # Pre-test assertion that the user we want to ban is present
      $do_request_json_for->( $banned_user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.member/${\$banned_user->user_id}",
      )->then( sub {
         my ( $body ) = @_;
         $body->{membership} eq "join" or
            die "Pretest assertion failed: expected user to be in 'join' state";

         $do_request_json_for->( $user,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/ban",

            content => { user_id => $banned_user->user_id, reason => "testing" },
         );
      })->then( sub {
         $do_request_json_for->( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$room_id/state/m.room.member/${\$banned_user->user_id}",
         );
      })->then( sub {
         my ( $body ) = @_;
         $body->{membership} eq "ban" or
            die "Expected banned user membership to be 'ban'";

         $do_request_json_for->( $banned_user,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/join",

            content => {},
         )->then(
            sub { # done
               die "Expected to receive an error joining the room when banned";
            },
            sub { # fail
               my ( $failure, $name ) = @_;
               defined $name and $name eq "http" or
                  die "Expected an HTTP failure";

               my ( undef, undef, $response, $request ) = @_;
               $response->code == 403 or
                  die "Expected an HTTP 403 error";

               Future->done(1);
            }
         );
      });
   };

test "Can invite existing 3pid",
   requires => [qw( user more_users test_http_server_uri_base do_request_json make_test_room await_http_request )],

   do => sub {
      my ( $user, $more_users, $test_http_server_uri_base, $do_request_json, $make_test_room, $await_http_request ) = @_;

      my $invitee_email = "marmosets\@monkeyworld.org";
      my $invitee_mxid = $more_users->[0]->user_id;
      my $room_id;

      Future->needs_all(
         stub_is_lookup($invitee_email, $invitee_mxid, $await_http_request),

         $make_test_room->("private", $user)
         ->then( sub {
            ( $room_id ) = @_;
            $do_request_json->(
               method => "POST",
               uri    => "/api/v1/rooms/$room_id/invite",

               content => {
                  id_server => (substr $test_http_server_uri_base, length("https://")),
                  medium => "email",
                  address => $invitee_email,
                  display_name => "Cute things",
               },
            ),
         })->then( sub {
            $do_request_json->(
               method => "GET",
               uri    => "/api/v1/rooms/$room_id/state/m.room.member/$invitee_mxid",
            )->on_done( sub {
               my ( $body ) = @_;
               log_if_fail $body;
               $body->{membership} eq "invite" or
                  die "Expected invited user membership to be 'invite'";
            }),
         }),
      );
   };

test "Can invite unbound 3pid",
   requires => [qw( user do_request_json do_request_json_for more_users test_http_server_uri_base make_test_room await_http_request )],

   do => sub {
      my ( $user, $do_request_json, $do_request_json_for, $more_users, $test_http_server_uri_base, $make_test_room, $await_http_request ) = @_;

      my $invitee = $more_users->[0];
      my $invitee_email = "lemurs\@monkeyworld.org";
      my $room_id;

      # sha256(abc+sha256(123lemurs@monkeyworld.org)
      # = sha256(abc+377e9ce9132221d02d9c76d0db6fe53f01552c1a7493e5001656882853e60299)
      # = 16c2f564f9f6ecdc26250d20dfd038198b75da6acef8c6f79b8092f19e8d82fa
      my $outer_nonce = "abc";
      my $inner_digest = "377e9ce9132221d02d9c76d0db6fe53f01552c1a7493e5001656882853e60299";
      my $outer_digest = "16c2f564f9f6ecdc26250d20dfd038198b75da6acef8c6f79b8092f19e8d82fa";

      $make_test_room->("private", $user)
      ->then( sub {
         ( $room_id ) = @_;
         Future->needs_all(
            stub_is_lookup($invitee_email, undef, $await_http_request),

            $await_http_request->("/_matrix/identity/api/v1/nonce-it-up", sub {
               my ( $raw_body, $req ) = @_;
               # TODO: Parse body
               return 1;
            })->then( sub {
               my ( $request ) = @_;
               $request->respond_json({nonce => $outer_nonce, digest => $outer_digest});
               Future->done( 1 );
            }),

            $do_request_json->(
               method => "POST",
               uri    => "/api/v1/rooms/$room_id/invite",

               content => {
                  id_server => (substr $test_http_server_uri_base, length("https://")),
                  medium => "email",
                  address => $invitee_email,
                  display_name => "Cool tails",
               }
            )->then( sub {
               $do_request_json_for->($invitee,
                  method => "POST",
                  uri    => "/api/v1/rooms/$room_id/join",

                  content => {
                     nonce => $outer_nonce,
                     secret => $inner_digest,
                     digest => $outer_digest,
                  }
               )
            })->then( sub {
               my ( $body ) = @_;
               my $invitee_mxid = $invitee->user_id;

               $do_request_json->(
                  method => "GET",
                  uri    => "/api/v1/rooms/$room_id/state/m.room.member/$invitee_mxid",
               )->on_done( sub {
                  my ( $body ) = @_;
                  log_if_fail Dumper($body);
                  $body->{membership} eq "join" or
                     die "Expected invited user membership to be 'join'";
               })
            }),
         )
      })
   };

sub stub_is_lookup {
   my ( $email, $mxid, $await_http_request ) = @_;
   $await_http_request->("/_matrix/identity/api/v1/lookup", sub {
      my ( $req ) = @_;
      return unless $req->query_param("medium") eq "email";
      return unless $req->query_param("address") eq $email;
      return 1;
   })->then( sub {
      my ( $request ) = @_;
      $request->respond_json(defined($mxid) ? {medium => "email", address => $email, mxid => $mxid} : {});
      Future->done( 1 );
   })
};

