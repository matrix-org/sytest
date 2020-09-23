use File::Basename qw( dirname );

use IO::Socket::IP 0.04; # ->sockhostname
Net::Async::HTTP->VERSION( '0.39' ); # ->GET with 'headers'

require IO::Async::SSL;

use Crypt::NaCl::Sodium;

use SyTest::Federation::Datastore;
use SyTest::Federation::Client;
use SyTest::Federation::Server;

push our @EXPORT, qw( INBOUND_SERVER OUTBOUND_CLIENT create_federation_server );

sub create_federation_server
{
   my $server = SyTest::Federation::Server->new;
   $loop->add( $server );

   start_test_server_ssl( $server )->on_done( sub {
      my ( $server ) = @_;
      my $sock = $server->read_handle;

      # Use $BIND_HOST here instead of $sock->sockhostname because both don't
      # always hold the same value, the federation certificate is generated for
      # $BIND_HOST, and we need the server's hostname to match the certificate's
      # common name.
      my $server_name = sprintf "%s:%d", $BIND_HOST, $sock->sockport;

      my ( $pkey, $skey ) = Crypt::NaCl::Sodium->sign->keypair;

      my $datastore = SyTest::Federation::Datastore->new(
         server_name => $server_name,
         key_id      => "ed25519:1",
         public_key  => $pkey,
         secret_key  => $skey,
      );

      my $outbound_client = SyTest::Federation::Client->new(
         datastore => $datastore,
         uri_base  => "/_matrix/federation",
        );
      $loop->add( $outbound_client );

      $server->configure(
         datastore => $datastore,
         client    => $outbound_client,
        );

      Future->done($server)
   });
}

our $INBOUND_SERVER = fixture(
   setup => sub {
      create_federation_server();
   }
);

our $OUTBOUND_CLIENT = fixture(
   requires => [ $INBOUND_SERVER ],

   setup => sub {
      my ( $inbound_server ) = @_;

      Future->done( $inbound_server->client );
   },
);

# A small test to check that our own federation server simulation is working
# correctly. If this test fails, it *ALWAYS* indicates a failure of SyTest
# itself and not of the homeserver being tested.
test "Checking local federation server",
   requires => [ $INBOUND_SERVER, $main::HTTP_CLIENT ],

   check => sub {
      my ( $inbound_server, $client ) = @_;

      my $key_id = $inbound_server->key_id;
      my $local_server_name = $inbound_server->server_name;

      $client->do_request(
         method => "GET",
         uri    => "https://$local_server_name/_matrix/key/v2/server/$key_id",
      )->then( sub {
         my ( $body ) = @_;
         log_if_fail "Keyserver response", $body;

         assert_json_keys( $body, qw( server_name valid_until_ts verify_keys signatures tls_fingerprints ));

         assert_json_string( $body->{server_name} );
         $body->{server_name} eq $local_server_name or
            die "Expected server_name to be $local_server_name";

         assert_json_number( $body->{valid_until_ts} );
         $body->{valid_until_ts} / 1000 > time or
            die "Key valid_until_ts is in the past";

         keys %{ $body->{verify_keys} } or
            die "Expected some verify_keys";

         exists $body->{verify_keys}{$key_id} or
            die "Expected to find the '$key_id' key in verify_keys";

         assert_json_keys( my $key = $body->{verify_keys}{$key_id}, qw( key ));

         assert_base64_unpadded( $key->{key} );

         keys %{ $body->{signatures} } or
            die "Expected some signatures";

         $body->{signatures}{$local_server_name} or
            die "Expected a signature from $local_server_name";

         my $signature = $body->{signatures}{$local_server_name}{$key_id} or
            die "Expected a signature from $local_server_name using $key_id";

         assert_base64_unpadded( $signature );

         # TODO: verify it?

         assert_json_list( $body->{tls_fingerprints} );
         @{ $body->{tls_fingerprints} } > 0 or
            die "Expected some tls_fingerprints";

         foreach ( @{ $body->{tls_fingerprints} } ) {
            assert_json_object( $_ );

            # TODO: Check it has keys named by the algorithms
         }

         Future->done(1);
      });
   };

=head2 send_and_await_event

   send_and_await_event( $outbound_client, $room, $user, %fields ) -> then( sub {
      my ( $event_id ) = @_;
   });

Send an event over federation and wait for it to turn up.

I<$outbound_client> should be a L<SyTest::Federation::Client>, most likely
I<$main::OUTBOUND_CLIENT>, which is used to send the event.

I<$room> should be the L<SyTest::Federation::Room> in which to send the event.

I<$user> should be a L<User> which will poll for receiving the event.

The remainder of the arguments (I<%fields>) are passed into
L<SyTest::Federation::Room/create_and_insert_event>. They should include at
least a C<sender>. C<type> and C<content> have defaults.

=cut

sub send_and_await_event {
   my ( $outbound_client, $room, $server_user, %fields ) = @_;
   my $server_name = $server_user->http->server_name;

   $fields{type} //= "m.room.message";
   $fields{content} //= { body => "hi" };

   my ( $event, $event_id ) = $room->create_and_insert_event( %fields );
   log_if_fail "Sending event $event_id in ".$room->room_id, $event;

   Future->needs_all(
      $outbound_client->send_event(
         event => $event,
         destination => $server_name,
      ),
      await_sync_timeline_contains(
         $server_user, $room->room_id, check => sub {
            $_[0]->{event_id} eq $event_id
         }
      ),
   )->then_done( $event_id );
}
push @EXPORT, qw( send_and_await_event );


my $next_user_id = 0;

=head2 federation_user_id_fixture

   $fixture = federation_user_id_fixture

Returns a new Fixture, which when provisioned will allocate a new user ID
within the "fake" internal federation context, and return it as a string.

=cut

sub federation_user_id_fixture
{
   fixture(
      requires => [ $INBOUND_SERVER ],

      setup => sub {
         my ( $inbound_server ) = @_;

         my $user_id = sprintf "\@__ANON__-%d:%s", $next_user_id++, $inbound_server->server_name;
         Future->done( $user_id );
      },
   );
}
push @EXPORT, qw( federation_user_id_fixture );


=head2 federated_rooms_fixture

   test "foo",
       requires => [ federated_rooms_fixture( %options ) ],
       do => sub {
           my ( $creator_user, $joining_user_id, $room1, $room2, ... ) = @_;
       };

Returns a new Fixture, which:

=over

=item * creates a user on the main test server

=item * uses that user to create one or more rooms

=item * uses a test user to join those rooms over federation

=back

The results of the Fixture are:

=over

=item * A User struct for the user on the server under test

=item * A string giving the user id of the sytest user which has joined the rooms

=item * A SyTest::Federation::Room object for each room

=back

The following options are supported:

=over

=item room_count => SCALAR

The number of rooms to be created. Defaults to 1.

=item room_opts => HASH

A set of options to be passed into C<matrix_create_room> for all of the rooms.

=back

=cut

sub federated_rooms_fixture {
   my %options = @_;

   my $room_count = $options{room_count} // 1;
   my $room_opts = $options{room_opts} // {};

   return fixture(
      requires => [
         local_user_fixture(),
         $main::OUTBOUND_CLIENT,
         federation_user_id_fixture(),
      ],

      setup => sub {
         my ( $synapse_user, $outbound_client, $sytest_user_id ) = @_;
         my $synapse_server_name = $synapse_user->http->server_name;

         my @rooms;

         repeat( sub {
            my ( $idx ) = @_;
            matrix_create_room( $synapse_user, %$room_opts )->then( sub {
               my ( $room_id ) = @_;
               $outbound_client->join_room(
                  server_name => $synapse_server_name,
                  room_id     => $room_id,
                  user_id     => $sytest_user_id,
               );
            })->on_done( sub {
               my ( $room ) = @_;
               log_if_fail "Joined room $idx: " . $room->room_id;
               push @rooms, $room;
            });
         }, foreach => [ 1 .. $room_count ]) -> then( sub {
            Future->done( $synapse_user, $sytest_user_id, @rooms );
         });
      },
   );
}

push @EXPORT, qw( federated_rooms_fixture );

=head2 federated_room_alias_fixture

   test "foo",
       requires => [ federated_room_alias_fixture() ],
       do => sub {
           my ( $room_alias ) = @_;
       };

Returns a new Fixture, which creates a unique room alias on the sytest federation server.

=cut

sub federated_room_alias_fixture {
   my %args = @_;

   return fixture(
      requires => [
         room_alias_name_fixture( prefix => $args{prefix} ),
         $main::INBOUND_SERVER,
      ],

      setup => sub {
         my ( $alias_name, $inbound_server ) = @_;
         Future->done( sprintf "#%s:%s", $alias_name, $inbound_server->server_name );
      },
   );
}

push @EXPORT, qw( federated_room_alias_fixture );
