use 5.014;  # s///r
use utf8;

# [U+2615] - HOT BEVERAGE
my $alias_localpart = "#☕";
my $room_alias;

my $creator_preparer = local_user_preparer();

my $room_preparer = room_preparer(
   requires_users => [ $creator_preparer ],
);

test "Room aliases can contain Unicode",
   requires => [qw( first_home_server ), $creator_preparer, $room_preparer,
                qw( can_create_room_alias )],

   provides => [qw( can_create_room_alias_unicode )],

   do => sub {
      my ( $first_home_server, $user, $room_id ) = @_;
      $room_alias = "${alias_localpart}:$first_home_server";

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/directory/room/$room_alias",

         content => { room_id => $room_id },
      );
   },

   check => sub {
      my ( $first_home_server, $user, $room_id ) = @_;
      $room_alias = "${alias_localpart}:$first_home_server";

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id ));

         $body->{room_id} eq $room_id or die "Expected room_id";

         provide can_create_room_alias_unicode => 1;

         Future->done(1);
      });
   };

test "Remote room alias queries can handle Unicode",
   requires => [ remote_user_preparer(), $room_preparer,
                 qw( can_create_room_alias_unicode )],

   provides => [qw( can_federate_room_alias_unicode )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         $body->{room_id} eq $room_id or die "Expected room_id";

         provide can_federate_room_alias_unicode => 1;

         Future->done(1);
      });
   };

multi_test "Canonical alias can be set",
   requires => [ local_user_preparer() ],

   do => sub {
      my ( $user ) = @_;

      my ( $room_id, $room_alias );

      matrix_create_room( $user,
         room_alias_name => "is-this-canonical",
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
