use 5.014;  # So we can use the /r flag to s///
use utf8;

# [U+2615] - HOT BEVERAGE
my $alias_localpart = "#☕";
my $room_alias;

my $creator_fixture = local_user_fixture();

my $room_fixture = room_fixture(
   requires_users => [ $creator_fixture ],
);

test "Room aliases can contain Unicode",
   requires => [ $creator_fixture, $room_fixture,
                 qw( can_create_room_alias )],

   proves => [qw( can_create_room_alias_unicode )],

   do => sub {
      my ( $user, $room_id ) = @_;
      my $server_name = $user->http->server_name;
      $room_alias = "${alias_localpart}:$server_name";

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/directory/room/$room_alias",

         content => { room_id => $room_id },
      );
   },

   check => sub {
      my ( $user, $room_id ) = @_;
      my $server_name = $user->http->server_name;
      $room_alias = "${alias_localpart}:$server_name";

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( room_id ));

         $body->{room_id} eq $room_id or die "Expected room_id";

         Future->done(1);
      });
   };

test "Remote room alias queries can handle Unicode",
   requires => [ remote_user_fixture(), $room_fixture,
                 qw( can_create_room_alias_unicode )],

   proves => [qw( can_federate_room_alias_unicode )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/r0/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         $body->{room_id} eq $room_id or die "Expected room_id";

         Future->done(1);
      });
   };

multi_test "Canonical alias can be set",
   requires => [ local_user_fixture(), room_alias_name_fixture() ],

   do => sub {
      my ( $user, $room_alias_name ) = @_;

      my ( $room_id, $room_alias );

      matrix_create_room( $user,
         room_alias_name => $room_alias_name,
      )->then( sub {
         ( $room_id, $room_alias ) = @_;

         matrix_put_room_state( $user, $room_id,
            type    => "m.room.canonical_alias",
            content => {
               alias => $room_alias,
            }
         )->SyTest::pass_on_done( "m.room.canonical_alias accepts present aliases" );
      })->then( sub {
         my $bad_alias = $room_alias =~ s/^#/#NOT-/r;

         matrix_put_room_state( $user, $room_id,
            type    => "m.room.canonical_alias",
            content => {
               alias => $bad_alias,
            }
         )->main::expect_http_4xx
            ->SyTest::pass_on_done( "m.room.canonical_alias rejects missing aliases" );
      });
   };
