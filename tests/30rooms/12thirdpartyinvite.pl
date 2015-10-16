use Crypt::NaCl::Sodium;
use File::Basename qw( dirname );
use Protocol::Matrix qw( encode_base64_unpadded );
use SyTest::Identity::Server;

my @user_preparers = local_user_preparers( 2 );

my $crypto_sign = Crypt::NaCl::Sodium->sign;

my $DIR = dirname( __FILE__ );

test "Can invite existing 3pid",
   requires => [ @user_preparers ],

   do => sub {
      my ( $inviter, $invitee ) = @_;

      my $invitee_email = 'marmosets@monkeyworld.org';
      my $invitee_mxid = $invitee->user_id;

      my $room_id;

      my $stub_id_server = SyTest::Identity::Server->new;
      $stub_id_server->{bindings}{$invitee_email} = $invitee_mxid;
      $loop->add( $stub_id_server );
      require IO::Async::SSL;
      $stub_id_server->listen(
         host    => "localhost",
         service => "",
         extensions => [qw( SSL )],
         # Synapse currently only talks IPv4
         family => "inet",

         SSL_cert_file => "$DIR/../../keys/tls-selfsigned.crt",
         SSL_key_file => "$DIR/../../keys/tls-selfsigned.key",
      )->then( sub {
         my ( $listener ) = @_;
         my $sock = $listener->read_handle;
         my $id_server = sprintf "%s:%d", $sock->sockhostname, $sock->sockport;
         Future->needs_all(
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
      });
   };

test "Can invite unbound 3pid",
   requires => [ @user_preparers, qw( first_home_server )],
   do => \&can_invite_unbound_3pid;

test "Can invite unbound 3pid over federation",
   requires => [ @user_preparers, qw( first_home_server )],
   do => \&can_invite_unbound_3pid;

sub can_invite_unbound_3pid
{
   my ( $inviter, $invitee, $user_agent ) = @_;

   make_3pid_invite(
      inviter             => $inviter,
      invitee             => $invitee,
      expect_join_success => 1,
      is_user_agent       => $user_agent,
      join_sub            => sub {
         my ( $token, $public_key, $signature, $room_id, $id_server ) = @_;

         do_request_json_for( $invitee,
            method  => "POST",
            uri     => "/api/v1/rooms/$room_id/join",
            content => {
               token            => $token,
               public_key       => $public_key,
               signature        => $signature,
               key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
               sender           => $inviter->user_id,
            }
         );
      },
   );
};

test "3pid invite join with wrong signature are rejected",
   requires => [ @user_preparers ],

   do => sub {
      my ( $user, $invitee ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id, $id_server ) = @_;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => $public_key,
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
      my ( $user, $invitee ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id, $id_server ) = @_;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => $public_key,
                  key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
                  sender           => $user->user_id,
               }
            );
         });
   };

test "3pid invite join with wrong key_validity_url are rejected",
   requires => [ @user_preparers, qw( test_http_server_hostandport )],

   do => sub {
      my ( $user, $invitee ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id, $id_server ) = @_;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => $public_key,
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
      my ( $user, $invitee ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id ) = @_;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token      => $token,
                  public_key => $public_key,
                  signature  => $signature,
                  sender     => $user->user_id,
               }
            );
         });
   };

test "3pid invite join with wrong signature are rejected",
   requires => [ @user_preparers, qw( test_http_server_hostandport )],

   do => sub {
      my ( $user, $invitee ) = @_;

      make_3pid_invite(
         inviter             => $user,
         invitee             => $invitee,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id, $id_server ) = @_;

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
   requires => [ @user_preparers ],

   do => sub {
      my ( $inviter, $invitee ) = @_;

      make_3pid_invite(
         inviter             => $inviter,
         invitee             => $invitee,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id, $id_server, $stub_id_server ) = @_;
            $stub_id_server->rotate_keys;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => $public_key,
                  signature        => $signature,
                  key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
                  sender           => $inviter->user_id,
               }
            );
         });
   };

test "3pid invite join fails if keyserver unreachable",
   requires => [ @user_preparers ],

   do => sub {
      my ( $inviter, $invitee ) = @_;

      make_3pid_invite(
         inviter             => $inviter,
         invitee             => $invitee,
         expect_join_success => 0,
         join_sub            => sub {
            my ( $token, $public_key, $signature, $room_id, $id_server, $stub_id_server ) = @_;
            $loop->remove( $stub_id_server );
            $stub_id_server->read_handle->close;

            do_request_json_for( $invitee,
               method  => "POST",
               uri     => "/api/v1/rooms/$room_id/join",
               content => {
                  token            => $token,
                  public_key       => $public_key,
                  signature        => $signature,
                  key_validity_url => "https://$id_server/_matrix/identity/api/v1/pubkey/isvalid",
                  sender           => $inviter->user_id,
               }
            );
         });
   };

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
   my $expect_join_success = $args{expect_join_success};
   my $join_sub = $args{join_sub};
   my $is_user_agent = $args{is_user_agent};

   my $invitee_email = 'lemurs@monkeyworld.org';
   my $token = "abc123";

   my $response_verifier = $expect_join_success
      ? sub { $_[0] } : \&main::expect_http_4xx;


   my $stub_id_server = SyTest::Identity::Server->new;
   $loop->add( $stub_id_server );
   $stub_id_server->listen(
      host    => "localhost",
      service => "",
      extensions => [qw( SSL )],
      # Synapse currently only talks IPv4
      family => "inet",

      SSL_cert_file => "$DIR/../../keys/tls-selfsigned.crt",
      SSL_key_file => "$DIR/../../keys/tls-selfsigned.key",
   )->then( sub {
      my ( $listener ) = @_;
      my $sock = $listener->read_handle;
      my $id_server = sprintf "%s:%d", $sock->sockhostname, $sock->sockport;
      if( defined $is_user_agent ) {
         $stub_id_server->{isvalid_needs_useragent} = $is_user_agent;
      }

      my @is_valid_stubs;
      my $room_id;

      Future->needs_all(
         matrix_create_room( $inviter, visibility => "private" )
         ->then(sub {
            ( $room_id ) = @_;
            $stub_id_server->stub_token( $token, "email", $invitee_email, $inviter->user_id, $room_id );
            do_3pid_invite( $inviter, $room_id, $id_server, $invitee_email )
         })->then( sub {
            my $signature = encode_base64_unpadded( $crypto_sign->mac( $token, $stub_id_server->{private_key} ) );
            $join_sub->( $token, $stub_id_server->{keys}{"ed25519:0"}, $signature, $room_id, $id_server, $stub_id_server )
         })->followed_by($response_verifier)
         ->then( sub {
            matrix_get_room_state( $inviter, $room_id,
               type      => "m.room.member",
               state_key => $invitee->user_id,
            )
         })->followed_by(assert_membership( $inviter, $expect_join_success ? "join" : undef ) ),
      );
   });
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
      : \&main::expect_http_error;
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
