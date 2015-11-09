use Crypt::NaCl::Sodium;
use File::Basename qw( dirname );
use IO::Async::SSL;
use Protocol::Matrix qw( encode_base64_unpadded sign_json );
use SyTest::Identity::Server;

my $crypto_sign = Crypt::NaCl::Sodium->sign;

my $DIR = dirname( __FILE__ );

my $invitee_email = 'lemurs@monkeyworld.org';

test "Can invite existing 3pid",
   requires => [ local_user_fixtures( 2 ), id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $id_server ) = @_;

      my $invitee_mxid = $invitee->user_id;

      my $room_id;

      $id_server->bind_identity( undef, "email", $invitee_email, $invitee )
      ->then( sub {
         matrix_create_and_join_room( [ $inviter ], visibility => "private" )
         ->then( sub {
            ( $room_id ) = @_;

            do_request_json_for( $inviter,
               method => "POST",
               uri    => "/api/v1/rooms/$room_id/invite",

               content => {
                  id_server    => $id_server->name,
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
         });
      });
   };

test "Can invite unbound 3pid",
   requires => [ local_user_fixtures( 2 ), qw( synapse_client_locations ),
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $locations, $id_server ) = @_;

      can_invite_unbound_3pid( $inviter, $invitee, $locations->[0], $id_server );
   };

test "Can invite unbound 3pid over federation",
   requires => [ local_user_fixture(), remote_user_fixture(), qw( synapse_client_locations ),
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $locations, $id_server ) = @_;

      can_invite_unbound_3pid( $inviter, $invitee, $locations->[1], $id_server );
   };

sub can_invite_unbound_3pid
{
   my ( $inviter, $invitee, $hs_uribase, $id_server ) = @_;

   my $room_id;

   matrix_create_room( $inviter, visibility => "private" )
   ->then( sub {
      ( $room_id ) = @_;

      do_3pid_invite( $inviter, $room_id, $id_server->name, $invitee_email )
   })->then( sub {
      $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee );
   })->then( sub {
      matrix_join_room( $invitee, $room_id )
   })->then( sub {
      matrix_get_room_state( $inviter, $room_id,
         type      => "m.room.member",
         state_key => $invitee->user_id,
      )
   })->followed_by( assert_membership( "join" ) );
}

test "Can accept unbound 3pid invite after inviter leaves",
   requires => [ local_user_fixtures( 3 ), qw( synapse_client_locations ),
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $other_member, $invitee, $locations, $id_server ) = @_;

      my $hs_uribase = $locations->[0];

      my $room_id;

      matrix_create_room( $inviter, visibility => "private" )
      ->then( sub {
         ( $room_id ) = @_;

          matrix_invite_user_to_room( $inviter, $other_member, $room_id );
      })->then( sub {
          matrix_join_room( $other_member, $room_id );
      })->then( sub {
         do_3pid_invite( $inviter, $room_id, $id_server->name, $invitee_email )
      })->then( sub {
         matrix_leave_room( $inviter, $room_id );
      })->then( sub {
         $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee );
      })->then( sub {
         matrix_join_room( $invitee, $room_id )
      })->then( sub {
         matrix_get_room_state( $other_member, $room_id,
            type      => "m.room.member",
            state_key => $invitee->user_id,
         )
      })->followed_by( assert_membership( "join" ) );
   };

test "3pid invite join with wrong but valid signature are rejected",
   requires => [ local_user_fixtures( 2 ), qw( synapse_client_locations ),
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $locations, $id_server ) = @_;
      my $hs_uribase = $locations->[0];

      invite_should_fail( $inviter, $invitee, $hs_uribase, $id_server, sub {
         $id_server->rotate_keys;
         $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee );
      });
   };

test "3pid invite join valid signature but revoked keys are rejected",
   requires => [ local_user_fixtures( 2 ), qw( synapse_client_locations ),
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $locations, $id_server ) = @_;
      my $hs_uribase = $locations->[0];

      invite_should_fail( $inviter, $invitee, $hs_uribase, $id_server, sub {
         $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee,
            sub { $id_server->rotate_keys } );
      });
   };

test "3pid invite join valid signature but unreachable ID server are rejected",
   requires => [ local_user_fixtures( 2 ), qw( synapse_client_locations ),
                    id_server_fixture() ],

   do => sub {
      my ( $inviter, $invitee, $locations, $id_server ) = @_;
      my $hs_uribase = $locations->[0];

      invite_should_fail( $inviter, $invitee, $hs_uribase, $id_server, sub {
         $id_server->bind_identity( $hs_uribase, "email", $invitee_email, $invitee, sub {
            $id_server->read_handle->close;
         })->then( sub {
            $loop->remove( $id_server );
            Future->done( 1 );
         });
      });
   };

sub invite_should_fail {
   my ( $inviter, $invitee, $hs_base_url, $id_server, $bind_sub ) = @_;

   my $room_id;

   matrix_create_room( $inviter, visibility => "private" )
   ->then( sub {
      ( $room_id ) = @_;

      do_3pid_invite( $inviter, $room_id, $id_server->name, $invitee_email )
   })->then( sub {
      $bind_sub->( $id_server );
   })->then( sub {
      matrix_join_room( $invitee, $room_id )
   })->followed_by(\&main::expect_http_4xx)->then( sub {
      matrix_get_room_state( $inviter, $room_id,
         type      => "m.room.member",
         state_key => $invitee->user_id,
      )
   })->followed_by(assert_membership( undef ) );
}

sub assert_membership {
   my ( $expected_membership ) = @_;

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
}

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
}

sub id_server_fixture
{
   return fixture(
      setup => sub {
         start_id_server();
      }
   );
}

sub start_id_server
{
   my $id_server = SyTest::Identity::Server->new;
   $loop->add( $id_server );
   $id_server->listen(
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
      my $id_server_hostandport = sprintf "%s:%d", $sock->sockhostname, $sock->sockport;
      Future->done( $id_server );
   })
}
