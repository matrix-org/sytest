use 5.014;  # So we can use the /r flag to s///
use utf8;
use List::Util qw( any none );

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

test "Creators can delete alias",
   requires => [ $creator_fixture, $room_fixture, room_alias_fixture(),
                 qw( can_create_room_alias )],

   do => sub {
      my ( $user, $room_id, $room_alias ) = @_;
      my $server_name = $user->http->server_name;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/directory/room/$room_alias",

         content => { room_id => $room_id },
      )->then( sub {
         do_request_json_for( $user,
           method => "DELETE",
           uri    => "/r0/directory/room/$room_alias",

           content => {},
         )
      })
   };

test "Users can't delete other's aliases",
   requires => [ $creator_fixture, $room_fixture, local_user_fixture(), room_alias_fixture(),
                 qw( can_create_room_alias )],

   do => sub {
      my ( $user, $room_id, $other_user, $room_alias ) = @_;
      my $server_name = $user->http->server_name;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/directory/room/$room_alias",

         content => { room_id => $room_id },
      )->then( sub {
         do_request_json_for( $other_user,
           method => "DELETE",
           uri    => "/r0/directory/room/$room_alias",

           content => {},
         )->main::expect_http_403;
      })
   };

test "Can delete canonical alias",
   requires => [ local_user_fixture( with_events => 0 ), room_alias_fixture(),
                 qw( can_create_room_alias )],

   do => sub {
      my ( $creator, $room_alias ) = @_;
      my $server_name = $creator->http->server_name;
      my $room_id;

      matrix_create_and_join_room( [ $creator ] )
      ->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $creator,
            method => "PUT",
            uri    => "/r0/directory/room/$room_alias",

            content => { room_id => $room_id },
         )
      })->then( sub {
         matrix_put_room_state( $creator, $room_id,
            type    => "m.room.canonical_alias",
            content => { alias => $room_alias }
         )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.aliases",
            state_key => $server_name,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( aliases ) );
         assert_json_list( my $aliases = $body->{aliases} );

         any { $_ eq $room_alias } @$aliases or die "Expected alias to be in list";

         do_request_json_for( $creator,
           method => "DELETE",
           uri    => "/r0/directory/room/$room_alias",

           content => {},
         )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.aliases",
            state_key => $server_name,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( aliases ) );
         assert_json_list( my $aliases = $body->{aliases} );

         none { $_ eq $room_alias } @$aliases or die "Expected alias to not be in list";

         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.canonical_alias",
         )
      })->then( sub {
         my ( $body ) = @_;

         not defined $body->{alias} or die "Expected canonical alias to be empty";

         Future->done( 1 );
      })
   };

test "Alias creators can delete alias with no ops",
   requires => [ local_user_fixtures( 2 ), room_alias_fixture(), qw( can_create_room_alias )],

   do => sub {
      my ( $creator, $other_user, $room_alias ) = @_;
      my $server_name = $creator->http->server_name;
      my $room_id;

      matrix_create_and_join_room( [ $creator, $other_user ] )
      ->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $other_user,
            method => "PUT",
            uri    => "/r0/directory/room/$room_alias",

            content => { room_id => $room_id },
         )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.aliases",
            state_key => $server_name,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( aliases ) );
         assert_json_list( my $aliases = $body->{aliases} );

         any { $_ eq $room_alias } @$aliases or die "Expected alias to be in list";

         do_request_json_for( $other_user,
           method => "DELETE",
           uri    => "/r0/directory/room/$room_alias",

           content => {},
         )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.aliases",
            state_key => $server_name,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( aliases ) );
         assert_json_list( my $aliases = $body->{aliases} );

         none { $_ eq $room_alias } @$aliases or die "Expected alias to not be in list";

         Future->done(1);
      })
   };

test "Alias creators can delete canonical alias with no ops",
   requires => [ local_user_fixtures( 2 ), room_alias_fixture(), qw( can_create_room_alias )],

   do => sub {
      my ( $creator, $other_user, $room_alias ) = @_;
      my $server_name = $creator->http->server_name;
      my $room_id;

      matrix_create_and_join_room( [ $creator, $other_user ] )
      ->then( sub {
         ( $room_id ) = @_;

         do_request_json_for( $other_user,
            method => "PUT",
            uri    => "/r0/directory/room/$room_alias",

            content => { room_id => $room_id },
         )
      })->then( sub {
         matrix_put_room_state( $creator, $room_id,
            type => "m.room.canonical_alias",
            content => { alias => $room_alias }
         )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.aliases",
            state_key => $server_name,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( aliases ) );
         assert_json_list( my $aliases = $body->{aliases} );

         any { $_ eq $room_alias } @$aliases or die "Expected alias to be in list";

         do_request_json_for( $other_user,
           method => "DELETE",
           uri    => "/r0/directory/room/$room_alias",

           content => {},
         )
      })->then( sub {
         matrix_get_room_state( $creator, $room_id,
            type      => "m.room.aliases",
            state_key => $server_name,
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( aliases ) );
         assert_json_list( my $aliases = $body->{aliases} );

         none { $_ eq $room_alias } @$aliases or die "Expected alias to not be in list";

         Future->done(1);
      })
   };
