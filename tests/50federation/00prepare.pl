use File::Basename qw( dirname );

use IO::Socket::IP 0.04; # ->sockhostname
Net::Async::HTTP->VERSION( '0.39' ); # ->GET with 'headers'

require IO::Async::SSL;

use SyTest::Federation::Datastore;
use SyTest::Federation::Client;
use SyTest::Federation::Server;
use SyTest::Crypto qw( ed25519_nacl_keypair );

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

      my ( $pkey, $skey ) = ed25519_nacl_keypair;

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

         assert_json_keys( $body, qw( server_name valid_until_ts verify_keys signatures ));

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

         Future->done(1);
      });
   };


=head2 await_and_handle_request_state

   $fut = await_and_handle_request_state(
       $inbound_server, $event_id, [ $state_event, $state_event, ... ],
       auth_chain => [ $auth_event, $auth_event, ... ],
   );

Awaits an inbound request to `/_matrix/federation/v1/state/$room_id?event_id=$event_id`,
and, when it arrives, sends a response with the given state.

I<auth_chain> is optional; if omitted, the auth chain is calculated based on
the given state events.

=cut

sub await_and_handle_request_state {
   my ( $inbound_server, $room, $event_id, $state_events, %args ) = @_;

   my $auth_chain = $args{auth_chain} // [
      map { $inbound_server->datastore->get_auth_chain_events( $room->id_for_event( $_ )) } @$state_events
   ];

   $inbound_server->await_request_v1_state(
      $room->room_id, $event_id,
   )->then( sub {
      my ( $req, @params ) = @_;
      log_if_fail "/state request", \@params;

      my $resp = {
         pdus => $state_events,
         auth_chain => $auth_chain,
      };

      log_if_fail "/state response", $resp;
      $req->respond_json( $resp );
   });
}
push @EXPORT, qw( await_and_handle_request_state );


=head2 send_and_await_event

   send_and_await_event( $outbound_client, $room, $server_user, %fields ) -> then( sub {
      my ( $event_id ) = @_;
   });

Send an event over federation and wait for it to turn up.

I<$outbound_client> should be a L<SyTest::Federation::Client>, most likely
I<$main::OUTBOUND_CLIENT>, which is used to send the event.

I<$room> should be the L<SyTest::Federation::Room> in which to send the event.

I<$server_user> should be a L<User> which will poll for receiving the event.

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


=head2 send_and_await_outlier

   send_and_await_outlier(
      $inbound_server, $outbound_client, $room, $sending_user_id, $receiving_user,
   )->then( sub {
      my ( $outlier_event ) = @_;
   });

Arranges for an outlier event to be sent over federation.

I<$inbound_server> should be a L<SyTest::Federation:Server>, likely
I<$main::INBOUND_SERVER>, which will handle the incoming federation requests
involved.

I<$outbound_client> should be a L<SyTest::Federation::Client>, most likely
I<$main::OUTBOUND_CLIENT>, which is used to send the event.

I<$room> should be the L<SyTest::Federation::Room> in which to send the event.

I<$sending_user_id> is a user on the Sytest federation server, and should be a
member of the room.

I<$receiving_user> should be a L<User> on the server under test, which will
poll for receiving the event. Must also be a member of the room.

The created outlier is returned.

=cut

sub send_and_await_outlier {
   my ( $inbound_server, $outbound_client, $room, $sending_user_id, $receiving_user ) = @_;

   # to construct an outlier, we create three events, Q, R, S.
   #
   # We send S over federation, and allow the server to backfill R, leaving
   # the server with a gap in the dag. It therefore requests the state at Q,
   # which leads to Q being persisted as an outlier.

   my $first_home_server = $receiving_user->server_name;
   my $room_id = $room->room_id;
   my %initial_room_state  = %{ $room->{current_state} };

   my ( $outlier_event_Q, $outlier_event_id_Q ) = $room->create_and_insert_event(
      type => 'm.room.member',
      sender => $sending_user_id,
      state_key => $sending_user_id,
      content => { membership => 'join' },
   );

   my ( $backfilled_event_R, $backfilled_event_id_R ) = $room->create_and_insert_event(
      type        => "m.room.message",
      sender      => $sending_user_id,
      content     => { body => "backfilled event R" },
   );

   my ( $sent_event_S, $sent_event_id_S ) = $room->create_and_insert_event(
      type        => "m.room.message",
      sender      => $sending_user_id,
      content     => { body => "sent event S" },
   );

   log_if_fail "create_outlier_event: events Q, R, S", [ $outlier_event_id_Q, $backfilled_event_id_R, $sent_event_id_S ];

   my $state_req_fut;

   Future->needs_all(
      # send S
      $outbound_client->send_event(
         event => $sent_event_S,
         destination => $first_home_server,
      ),

      # we expect to get a missing_events request
      $inbound_server->await_request_get_missing_events( $room_id )
      ->then( sub {
         my ( $req ) = @_;
         my $body = $req->body_from_json;
         log_if_fail "create_outlier_event: /get_missing_events request", $body;

         assert_deeply_eq(
            $body->{latest_events},
            [ $sent_event_id_S ],
            "create_outlier_event: latest_events in /get_missing_events request",
        );

        # just return R
        my $resp = { events => [ $backfilled_event_R ] };

        log_if_fail "create_outlier_event: /get_missing_events response", $resp;
        $req->respond_json( $resp );
        Future->done(1);
      }),

      # there will still be a gap, so then we expect a state_ids request
      $inbound_server->await_request_state_ids(
         $room_id, $outlier_event_id_Q,
      )->then( sub {
         my ( $req, @params ) = @_;
         log_if_fail "create_outlier_event: /state_ids request", \@params;

         my $resp = {
            pdu_ids => [
               map { $room->id_for_event( $_ ) } values( %initial_room_state ),
            ],
            auth_chain_ids => $room->event_ids_from_refs( $outlier_event_Q->{auth_events} ),
         };

         log_if_fail "create_outlier_event: /state_ids response", $resp;

         # once we respond to `/state_ids`, the server may send a /state request;
         # be prepared to answer that.  (it may, alternatively, send individual
         # /event requests)
         $state_req_fut = await_and_handle_request_state(
            $inbound_server, $room, $outlier_event_id_Q, [ values( %initial_room_state ) ]
         );

         $req->respond_json( $resp );
         Future->done(1);
      }),
   )->then( sub {
      # wait for either S to turn up in /sync, or $state_req_fut to fail.
      Future->wait_any(
         $state_req_fut->then( sub { Future->new() } ),

         await_sync_timeline_contains(
            $receiving_user, $room_id, check => sub {
               my ( $event ) = @_;
               log_if_fail "create_outlier_event: Got event", $event;
               my $event_id = $event->{event_id};
               return $event_id eq $sent_event_id_S;
            },
         ),
      );
   })->then_done( $outlier_event_Q, $backfilled_event_R, $sent_event_S );
}
push @EXPORT, qw( send_and_await_outlier );


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
