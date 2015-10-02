use utf8;

# [U+2615] - HOT BEVERAGE
my $alias_localpart = "#☕";
my $room_id;
my $room_alias;

prepare "Creating a test room",
   requires => [qw( user )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user )
      ->on_done( sub {
         ( $room_id ) = @_;
      });
   };

test "Room aliases can contain Unicode",
   requires => [qw( user first_home_server
                    can_create_room_alias )],

   provides => [qw( can_create_room_alias_unicode )],

   do => sub {
      my ( $user, $first_home_server ) = @_;
      $room_alias = "${alias_localpart}:$first_home_server";

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/directory/room/$room_alias",

         content => { room_id => $room_id },
      );
   },

   check => sub {
      my ( $user, $first_home_server ) = @_;
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
   requires => [qw( remote_users
                    can_create_room_alias_unicode )],

   provides => [qw( can_federate_room_alias_unicode )],

   check => sub {
      my ( $remote_users ) = @_;
      my $user = $remote_users->[0];

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
