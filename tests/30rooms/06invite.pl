use Crypt::NaCl::Sodium;
use List::Util qw( first );
use Protocol::Matrix qw( encode_json_for_signing encode_base64_unpadded );

my $inviteonly_room_id;

my $crypto_sign = Crypt::NaCl::Sodium->sign;

test "A room can be created set to invite-only",
   requires => [qw( user )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user,
         # visibility: "private" actually means join_rule: "invite"
         # See SPEC-74
         visibility => "private",
      )->then( sub {
         ( $inviteonly_room_id ) = @_;

         do_request_json_for( $user,
            method => "GET",
            uri    => "/api/v1/rooms/$inviteonly_room_id/initialSync",
         )->then( sub {
            my ( $body ) = @_;

            require_json_keys( $body, qw( state ));

            my ( $join_rules_event ) = first { $_->{type} eq "m.room.join_rules" } @{ $body->{state} };
            $join_rules_event or
               die "Failed to find an m.room.join_rules event";

            $join_rules_event->{content}{join_rule} eq "invite" or
               die "Expected join rule to be 'invite'";

            Future->done(1);
         });
      });
   };

test "Uninvited users cannot join the room",
   requires => [qw( more_users )],

   check => sub {
      my ( $more_users ) = @_;
      my $uninvited = $more_users->[0];

      matrix_join_room( $uninvited, $inviteonly_room_id )
         ->main::expect_http_403;
   };

test "Can invite users to invite-only rooms",
   requires => [qw( user more_users
                    can_invite_room )],

   do => sub {
      my ( $user, $more_users ) = @_;
      my $invitee = $more_users->[1];

      matrix_invite_user_to_room( $user, $invitee, $inviteonly_room_id )
   };

test "Invited user receives invite",
   requires => [qw( more_users
                    can_invite_room )],

   do => sub {
      my ( $more_users ) = @_;
      my $invitee = $more_users->[1];

      await_event_for( $invitee, sub {
         my ( $event ) = @_;

         require_json_keys( $event, qw( type ));
         return 0 unless $event->{type} eq "m.room.member";

         require_json_keys( $event, qw( room_id state_key ));
         return 0 unless $event->{room_id} eq $inviteonly_room_id;
         return 0 unless $event->{state_key} eq $invitee->user_id;

         require_json_keys( my $content = $event->{content}, qw( membership ));

         $content->{membership} eq "invite" or
            die "Expected membership to be 'invite'";

         return 1;
      });
   };

test "Invited user can join the room",
   requires => [qw( more_users
                    can_invite_room )],

   do => sub {
      my ( $more_users ) = @_;
      my $invitee = $more_users->[1];

      matrix_join_room( $invitee, $inviteonly_room_id )
      ->then( sub {
         matrix_get_room_state( $invitee, $inviteonly_room_id,
            type      => "m.room.member",
            state_key => $invitee->user_id,
         )
      })->then( sub {
         my ( $member_state ) = @_;

         $member_state->{membership} eq "join" or
            die "Expected my membership to be 'join'";

         Future->done(1);
      });
   };

test "Can invite existing 3pid",
   requires => [qw( user more_users test_http_server_hostandport await_http_request )],

   do => sub {
      my ( $inviter, $more_users, $id_server, $await_http_request ) = @_;

      my $invitee_email = "marmosets\@monkeyworld.org";
      my $invitee_mxid = $more_users->[0]->user_id;
      my $room_id;

      Future->needs_all(
         stub_is_lookup( $invitee_email, $invitee_mxid, $await_http_request ),

         matrix_create_and_join_room( [ $inviter ], visibility => "private" )
         ->then( sub {
            ( $room_id ) = @_;
            do_request_json_for( $inviter,
               method => "POST",
               uri    => "/api/v1/rooms/$room_id/invite",

               content => {
                  id_server => $id_server,
                  medium => "email",
                  address => $invitee_email,
                  display_name => "Cute things",
               },
            ),
         })->then( sub {
            matrix_get_room_state( $inviter, $room_id,
               type => "m.room.member",
               state_key => $invitee_mxid,
            )->on_done( sub {
               my ( $body ) = @_;

               log_if_fail "Body", $body;
               $body->{membership} eq "invite" or
                  die "Expected invited user membership to be 'invite'";
            });
         }),
      );
   };

test "Can invite unbound 3pid",
   requires => [qw( user more_users test_http_server_hostandport await_http_request first_home_server )],
   do => \&can_invite_unbound_3pid;

test "Can invite unbound 3pid over federation",
   requires => [qw( user remote_users test_http_server_hostandport await_http_request first_home_server )],
   do => \&can_invite_unbound_3pid;

sub can_invite_unbound_3pid {
   my ( $inviter, $other_users, $id_server, $await_http_request, $user_agent ) = @_;
   my $invitee = $other_users->[0];

   make_3pid_invite( $inviter, $invitee, $id_server, $await_http_request, 1, sub {
      my ( $token, $public_key, $signature, $room_id ) = @_;

      do_request_json_for( $invitee,
         method => "POST",
         uri    => "/api/v1/rooms/$room_id/join",
         content => {
            token => $token,
            public_key => encode_base64_unpadded( $public_key ),
            signature => $signature,
            key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
            sender => $inviter->user_id,
         }
      );
   },
   [ stub_is_key_validation( JSON::true, $await_http_request, $user_agent ) ] );
};

test "3pid invite join with wrong signature are rejected",
   requires => [qw( user more_users test_http_server_hostandport await_http_request )],
   do => sub {
      my ( $user, $other_users, $id_server, $await_http_request ) = @_;
      my $invitee = $other_users->[0];

      make_3pid_invite( $user, $invitee, $id_server, $await_http_request, 0, sub {
         my ( $token, $public_key, $signature, $room_id ) = @_;

         do_request_json_for( $invitee,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/join",
            content => {
               token => $token,
               public_key => encode_base64_unpadded( $public_key ),
               signature => "abc",
               key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
               sender => $user->user_id,
            }
         );
      },
      # This should really be an optional stub
      #[ stub_is_key_validation( JSON::true, $await_http_request ) ],
      [],
      );
   };

test "3pid invite join with missing signature are rejected",
   requires => [qw( user more_users test_http_server_hostandport await_http_request )],
   do => sub {
      my ( $user, $other_users, $id_server, $await_http_request ) = @_;
      my $invitee = $other_users->[0];

      make_3pid_invite( $user, $invitee, $id_server, $await_http_request, 0, sub {
         my ( $token, $public_key, $signature, $room_id ) = @_;

         do_request_json_for( $invitee,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/join",
            content => {
               token => $token,
               public_key => encode_base64_unpadded( $public_key ),
               key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
               sender => $user->user_id,
            }
         );
      },
      [],
      );
   };

test "3pid invite join with wrong key_validity_url are rejected",
   requires => [qw( user more_users test_http_server_hostandport await_http_request )],
   do => sub {
      my ( $user, $other_users, $id_server, $await_http_request ) = @_;
      my $invitee = $other_users->[0];

      make_3pid_invite( $user, $invitee, $id_server, $await_http_request, 0, sub {
         my ( $token, $public_key, $signature, $room_id ) = @_;

         do_request_json_for( $invitee,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/join",
            content => {
               token => $token,
               public_key => encode_base64_unpadded( $public_key ),
               signature => $signature,
               key_validity_url => "https://wrongdoesnotexist$id_server/_matrix/identity/api/v1/pubkey/isvalid",
               sender => $user->user_id,
            }
         );
      },
      [],
      );
   };

test "3pid invite join with missing key_validity_url are rejected",
   requires => [qw( user more_users test_http_server_hostandport await_http_request )],
   do => sub {
      my ( $user, $other_users, $id_server, $await_http_request ) = @_;
      my $invitee = $other_users->[0];

      make_3pid_invite( $user, $invitee, $id_server, $await_http_request, 0, sub {
         my ( $token, $public_key, $signature, $room_id ) = @_;

         do_request_json_for( $invitee,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/join",
            content => {
               token => $token,
               public_key => encode_base64_unpadded( $public_key ),
               signature => $signature,
               sender => $user->user_id,
            }
         );
      },
      [],
      );
   };

test "3pid invite join with wrong signature are rejected",
   requires => [qw( user more_users test_http_server_hostandport await_http_request )],
   do => sub {
      my ( $user, $other_users, $id_server, $await_http_request ) = @_;
      my $invitee = $other_users->[0];

      make_3pid_invite( $user, $invitee, $id_server, $await_http_request, 0, sub {
         my ( $token, $public_key, $signature, $room_id ) = @_;

         my ( $wrong_public_key, $wrong_private_key ) = $crypto_sign->keypair;

         do_request_json_for( $invitee,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/join",
            content => {
               token => $token,
               public_key => encode_base64_unpadded( $wrong_public_key ),
               signature => encode_base64_unpadded( $crypto_sign->mac( $token, $wrong_private_key ) ),
               key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
               sender => $user->user_id,
            }
         );
      },
      [],
      );
   };

test "3pid invite join fails if key revoked",
   requires => [qw( user more_users test_http_server_hostandport await_http_request )],
   do => sub {
      my ( $inviter, $other_users, $id_server, $await_http_request ) = @_;
      my $invitee = $other_users->[0];

      make_3pid_invite ($inviter, $invitee, $id_server, $await_http_request, 0, sub {
         my ( $token, $public_key, $signature, $room_id ) = @_;

         do_request_json_for( $invitee,
            method => "POST",
            uri    => "/api/v1/rooms/$room_id/join",
            content => {
               token => $token,
               public_key => encode_base64_unpadded( $public_key ),
               signature => $signature,
               key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
               sender => $inviter->user_id,
            }
         );
      },
      [ stub_is_key_validation( JSON::false, $await_http_request ) ],
      );
   };

# TODO: Work out how to require an id_server which only listens for one request then closes the socket
#test "3pid invite join fails if keyserver cannot be reached",
#   requires => [qw( user more_users test_http_server_hostandport await_http_request )],
#   do => sub {
#      my ( $user, $other_users, $id_server, $make_test_room, $await_http_request ) = @_;
#
#      my $non_existent_id_server = "ireallyhopethishostdoesnotexist";
#      my $invitee_email = 'lemurs@monkeyworld.org';
#      my $inviter = $user;
#      my $invitee = $other_users->[0];
#
#      my $token = "abc123";
#
#      my ( $public_key, $private_key ) = $crypto_sign->keypair;
#      my $encoded_public_key = encode_base64_unpadded( $public_key );
#      my $signature = encode_base64_unpadded( $crypto_sign->mac( $token, $private_key ) );
#
#      Future->needs_all(
#         stub_is_lookup( $invitee_email, undef, $await_http_request ),
#
#         stub_is_token_generation( $token, $encoded_public_key, $await_http_request ),
#
#         matrix_create_room->( $inviter, visibility => "private" )
#         ->then(sub {
#            my ( $room_id ) = @_;
#            do_3pid_invite( $room_id, $id_server, $invitee_email, $do_request_json )
#            ->then( sub {
#               do_request_json_for( $invitee,
#                  method => "POST",
#                  uri    => "/api/v1/rooms/$room_id/join",
#                  content => {
#                     token => $token,
#                     public_key => encode_base64_unpadded( $public_key ),
#                     signature => $signature,
#                     key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
#                     sender => $user->user_id,
#                  }
#               )
#               ->followed_by(\&main::expect_http_4xx)
#               ->then( sub {
#                  $do_request_json->(
#                     method => "GET",
#                     uri    => "/api/v1/rooms/$room_id/state/m.room.member/".$invitee->user_id,
#                  )->followed_by(assert_membership( $do_request_json, $inviter, undef ) )
#               })
#            })
#         }),
#      );
#   };

# In order:
#  1. Creates all state needed to issue a 3pid invite
#  2. Issues the invite
#  3. Calls join_sub with the following args: token (str), public_key (base64 str), $signature (base64 str), room_id (str)
#  4. Asserts that invitee did/didn't join the room, depending on truthiness of expect_join_success
#  5. Awaits on all passed futures, so that you can stub/mock things as you wish
sub make_3pid_invite {
   my ( $inviter, $invitee, $id_server, $await_http_request, $expect_join_success, $join_sub, $futures ) = @_;

   my $invitee_email = 'lemurs@monkeyworld.org';

   my $token = "abc123";

   my ( $public_key, $private_key ) = $crypto_sign->keypair;
   my $encoded_public_key = encode_base64_unpadded( $public_key );
   my $signature = encode_base64_unpadded( $crypto_sign->mac( $token, $private_key ) );

   my $response_verifier = $expect_join_success
      ? sub {
         my ( $f ) = @_;
         $f->then( sub {
            Future->done( @_ );
         }, sub {
            my ( undef, $name, $response ) = @_;

            Future->fail( @_ );
         });
      }
      : \&main::expect_http_4xx;

   my $room_id;

   Future->needs_all(
      stub_is_lookup( $invitee_email, undef, $await_http_request ),

      stub_is_token_generation( $token, $encoded_public_key, $await_http_request ),

      @$futures,

      matrix_create_room( $inviter, visibility => "private" )
      ->then(sub {
         ( $room_id ) = @_;
         do_3pid_invite( $inviter, $room_id, $id_server, $invitee_email )
      })->then( sub {
         $join_sub->( $token, $public_key, $signature, $room_id )
      })->followed_by($response_verifier)
      ->then( sub {
         matrix_get_room_state( $inviter, $room_id,
            type => "m.room.member",
            state_key => $invitee->user_id,
         )
      })->followed_by(assert_membership( $inviter, $expect_join_success ? "join" : undef ) ),
   );
}

sub assert_membership {
   my ( $user, $expected_membership ) = @_;

   my $verifier = defined $expected_membership
      ? sub {
         my ( $f ) = @_;

         $f->then( sub {
            my ( $body ) = @_;

            log_if_fail "Body", $body;
            $body->{membership} eq $expected_membership or
               die "Expected invited user membership to be '$expected_membership' but was '".$body->membership."'";

            Future->done( 1 );
         } )
      }
      : \&main::expect_http_404;
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

sub stub_is_token_generation {
   my ( $token, $encoded_public_key, $await_http_request ) = @_;

   $await_http_request->( "/_matrix/identity/api/v1/nonce-it-up", sub {
      my ( $req ) = @_;
      # TODO: Parse body
      return 1;
   })->then( sub {
      my ( $request ) = @_;
      $request->respond_json( {
            token => $token,
            public_key => $encoded_public_key,
         } );
      Future->done( 1 );
   })
};

sub stub_is_key_validation {
   my ( $validity, $await_http_request, $wanted_user_agent_substring ) = @_;

   $await_http_request->( "/_matrix/identity/api/v1/pubkey/isvalid", sub {
      my ( $req ) = @_;
      !defined $wanted_user_agent_substring and return 1;
      my $user_agent = $req->header( "User-Agent" );
      defined $user_agent and $user_agent =~ m/\Q$wanted_user_agent_substring/ or
         return 0;
      # TODO: Parse body
      return 1;
   })->then( sub {
      my ( $request ) = @_;
      $request->respond_json( { valid => $validity } );
      Future->done( 1 );
   })
};

sub do_3pid_invite {
   my ( $inviter, $room_id, $id_server, $invitee_email ) = @_;

   do_request_json_for( $inviter,
      method => "POST",
      uri    => "/api/v1/rooms/$room_id/invite",

      content => {
         id_server => $id_server,
         medium => "email",
         address => $invitee_email,
         display_name => "Cool tails",
      }
   )
};
