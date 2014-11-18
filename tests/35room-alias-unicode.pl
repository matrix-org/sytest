use utf8;

# [U+2615] - HOT BEVERAGE
my $alias_localpart = "#☕";
my $room_alias;

test "Room aliases can contain Unicode",
   requires => [qw( do_request_json room_id first_home_server
                    can_create_room_alias )],

   do => sub {
      my ( $do_request_json, $room_id, $first_home_server ) = @_;
      $room_alias = "${alias_localpart}:$first_home_server";

      $do_request_json->(
         method => "PUT",
         uri    => "/directory/room/$room_alias",

         content => { room_id => $room_id },
      );
   },

   check => sub {
      my ( $do_request_json, $room_id, $first_home_server ) = @_;
      $room_alias = "${alias_localpart}:$first_home_server";

      $do_request_json->(
         method => "GET",
         uri    => "/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( room_id ));

         $body->{room_id} eq $room_id or die "Expected room_id";

         provide can_create_room_alias_unicode => 1;

         Future->done(1);
      });
   };

test "Remote room alias queries can handle Unicode",
   requires => [qw( do_request_json_for remote_users room_id
                    can_create_room_alias_unicode )],

   check => sub {
      my ( $do_request_json_for, $remote_users, $room_id ) = @_;
      my $user = $remote_users->[0];

      $do_request_json_for->( $user,
         method => "GET",
         uri    => "/directory/room/$room_alias",
      )->then( sub {
         my ( $body ) = @_;

         $body->{room_id} eq $room_id or die "Expected room_id";

         provide can_federate_room_alias_unicode => 1;

         Future->done(1);
      });
   };
