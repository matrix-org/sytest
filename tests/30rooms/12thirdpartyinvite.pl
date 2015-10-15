use Crypt::NaCl::Sodium;
use Protocol::Matrix qw( encode_json_for_signing encode_base64_unpadded );

my @user_preparers = local_user_preparers( 2 );

my $crypto_sign = Crypt::NaCl::Sodium->sign;

test "Can invite existing 3pid",
   requires => [ @user_preparers, qw( test_http_server_hostandport )],

   do => sub {
      my ( $inviter, $invitee, $id_server ) = @_;

      my $invitee_email = 'marmosets@monkeyworld.org';
      my $invitee_mxid = $invitee->user_id;

      my $room_id;

      Future->needs_all(
         stub_is_lookup( $invitee_email, $invitee_mxid ),

         matrix_create_and_join_room( [ $inviter ], visibility => "private" )
         ->then( sub {
            ( $room_id ) = @_;
            do_request_json_for( $inviter,
               method => "POST",
               uri    => "/api/v1/rooms/$room_id/invite",

               content => {
                  id_server    => $id_server,
                  medium       => "email",
                  address      => $invitee_email,
                  display_name => "Cute things",
               },
            );
         })->then( sub {
            matrix_get_room_state( $inviter, $room_id,
               type      => "m.room.member",
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
   requires => [ @user_preparers, qw( test_http_server_hostandport first_home_server )],
   do => \&can_invite_unbound_3pid;

test "Can invite unbound 3pid over federation",
   requires => [ @user_preparers, qw( test_http_server_hostandport first_home_server )],
   do => \&can_invite_unbound_3pid;

sub can_invite_unbound_3pid
{
   my ( $inviter, $invitee, $id_server, $user_agent ) = @_;

   make_3pid_invite(
      inviter             => $inviter,
      invitee             => $invitee,
      id_server           => $id_server,
      expect_join_success => 1,
      is_key_validity     => 1,
      is_user_agent       => $user_agent,
      join_sub            => sub {
         my ( $token, $public_key, $signature, $room_id ) = @_;

         do_request_json_for( $invitee,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/join",
            content => {
               token            => $token,
               public_key       => encode_base64_unpadded( $public_key ),
               signature        => $signature,
               key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
               sender           => $inviter->user_id,
            }
         );
      },
   );
};

test "3pid invite join with wrong signature are rejected",
   requires => [ @user_preparers, qw( test_http_server_hostandport )],

   do => sub {
      my ( $user, $invitee, $id_server ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         id_server           => $id_server,
         expect_join_success => 0,
         is_key_validity     => undef, # Should really be an optionally called stub for true
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id ) = @_;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => encode_base64_unpadded( $public_key ),
                  signature        => "abc",
                  key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
                  sender           => $user->user_id,
               }
            );
         });
   };

test "3pid invite join with missing signature are rejected",
   requires => [ @user_preparers, qw( test_http_server_hostandport )],

   do => sub {
      my ( $user, $invitee, $id_server ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         id_server           => $id_server,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id ) = @_;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => encode_base64_unpadded( $public_key ),
                  key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
                  sender           => $user->user_id,
               }
            );
         });
   };

test "3pid invite join with wrong key_validity_url are rejected",
   requires => [ @user_preparers, qw( test_http_server_hostandport )],

   do => sub {
      my ( $user, $invitee, $id_server ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         id_server           => $id_server,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id ) = @_;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => encode_base64_unpadded( $public_key ),
                  signature        => $signature,
                  key_validity_url => "https://wrongdoesnotexist$id_server/_matrix/identity/api/v1/pubkey/isvalid",
                  sender           => $user->user_id,
               }
            );
         });
   };

test "3pid invite join with missing key_validity_url are rejected",
   requires => [ @user_preparers, qw( test_http_server_hostandport )],

   do => sub {
      my ( $user, $invitee, $id_server ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         id_server           => $id_server,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id ) = @_;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token      => $token,
                  public_key => encode_base64_unpadded( $public_key ),
                  signature  => $signature,
                  sender     => $user->user_id,
               }
            );
         });
   };

test "3pid invite join with wrong signature are rejected",
   requires => [ @user_preparers, qw( test_http_server_hostandport )],

   do => sub {
      my ( $user, $invitee, $id_server ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         id_server           => $id_server,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id ) = @_;

            my ( $wrong_public_key, $wrong_private_key ) = $crypto_sign->keypair;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => encode_base64_unpadded( $wrong_public_key ),
                  signature        => encode_base64_unpadded( $crypto_sign->mac( $token, $wrong_private_key ) ),
                  key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
                  sender           => $user->user_id,
               }
            );
         });
   };

test "3pid invite join fails if key revoked",
   requires => [ @user_preparers, qw( test_http_server_hostandport )],

   do => sub {
      my ( $inviter, $invitee, $id_server ) = @_;

      make_3pid_invite(
         inviter             => $inviter,
         invitee             => $invitee,
         id_server           => $id_server,
         expect_join_success => 0,
         is_key_validity     => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id ) = @_;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => encode_base64_unpadded( $public_key ),
                  signature        => $signature,
                  key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
                  sender           => $inviter->user_id,
               }
            );
         });
   };

# TODO: Work out how to require an id_server which only listens for one request then closes the socket
#test "3pid invite join fails if keyserver cannot be reached",
#   requires => [qw( user more_users test_http_server_hostandport )],
#   do => sub {
#      my ( $user, $other_users, $id_server, $make_test_room ) = @_;
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
#         stub_is_lookup( $invitee_email, undef ),
#
#         stub_is_token_generation( $token, $encoded_public_key ),
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
   my %args = @_;
   my $inviter = $args{inviter};
   my $invitee = $args{invitee};
   my $id_server = $args{id_server};
   my $expect_join_success = $args{expect_join_success};
   my $join_sub = $args{join_sub};
   my $is_key_validity = $args{is_key_validity}; # May be 0/1/undef
   my $is_user_agent = $args{is_user_agent};

   my $invitee_email = 'lemurs@monkeyworld.org';

   my $token = "abc123";

   my ( $public_key, $private_key ) = $crypto_sign->keypair;
   my $encoded_public_key = encode_base64_unpadded( $public_key );
   my $signature = encode_base64_unpadded( $crypto_sign->mac( $token, $private_key ) );

   my $response_verifier = $expect_join_success
      ? sub { $_[0] } : \&main::expect_http_4xx;

   my @is_valid_stubs;
   push @is_valid_stubs, stub_is_key_validation( $is_key_validity ? JSON::true : JSON::false, $is_user_agent, $encoded_public_key )
      if defined $is_key_validity;
   my $room_id;

   Future->needs_all(
      stub_is_lookup( $invitee_email, undef ),

      stub_is_token_generation( $token, $encoded_public_key, $inviter, $invitee_email ),

      @is_valid_stubs,

      matrix_create_room( $inviter, visibility => "private" )
      ->then(sub {
         ( $room_id ) = @_;
         do_3pid_invite( $inviter, $room_id, $id_server, $invitee_email )
      })->then( sub {
         $join_sub->( $token, $public_key, $signature, $room_id )
      })->followed_by($response_verifier)
      ->then( sub {
         matrix_get_room_state( $inviter, $room_id,
            type      => "m.room.member",
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
               die "Expected invited user membership to be '$expected_membership'";

            Future->done( 1 );
         } )
      }
      : \&main::expect_http_404;
};

sub stub_is_lookup {
   my ( $email, $mxid ) = @_;

   await_http_request("/_matrix/identity/api/v1/lookup", sub {
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
   my ( $token, $encoded_public_key, $inviter, $invitee_email ) = @_;

   await_http_request( "/_matrix/identity/api/v1/nonce-it-up", sub {
      my ( $req ) = @_;

      my $body = $req->body_from_form;
      log_if_fail "IS token generation body", $body;
      exists $body->{medium} and $body->{medium} eq "email" or return;
      exists $body->{address} and $body->{address} eq $invitee_email or return;
      exists $body->{sender} and $body->{sender} eq $invitee_email or return
      exists $body->{room_id} or return
      return 1;
   })->then( sub {
      my ( $request ) = @_;
      $request->respond_json( {
            token      => $token,
            public_key => $encoded_public_key,
         } );
      Future->done( 1 );
   })
};

sub stub_is_key_validation {
   my ( $validity, $wanted_user_agent_substring, $public_key ) = @_;

   await_http_request( "/_matrix/identity/api/v1/pubkey/isvalid", sub {
      my ( $req ) = @_;
      !defined $wanted_user_agent_substring and return 1;
      my $user_agent = $req->header( "User-Agent" );
      defined $user_agent and $user_agent =~ m/\Q$wanted_user_agent_substring/ or
         return 0;
      $req->query_param("public_key") eq $public_key or return;
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
      method  => "POST",
      uri     => "/api/v1/rooms/$room_id/invite",
      content => {
         id_server    => $id_server,
         medium       => "email",
         address      => $invitee_email,
         display_name => "Cool tails",
      }
   )
};
