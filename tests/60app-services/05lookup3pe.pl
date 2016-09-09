use List::UtilsBy qw( sort_by );

use constant AS_PREFIX => "/_matrix/app/unstable";

sub stub_empty_result
{
   my ( $appserv, $path ) = @_;

   $appserv->await_http_request( AS_PREFIX . $path, sub { 1 } )->then( sub {
      my ( $request ) = @_;

      $request->respond_json( [] );
      Future->done;
   });
}

test "HS provides query metadata",
   requires => [ local_user_fixture(), $main::APPSERV[0], $main::APPSERV[1] ],

   proves => [qw( can_get_3pe_metadata )],

   check => sub {
      my ( $user, $appserv1, $appserv2 ) = @_;

      Future->needs_all(
         $appserv1->await_http_request( AS_PREFIX . "/thirdparty/protocol/ymca",
            sub { 1 }
         )->then( sub {
            my ( $request ) = @_;

            $request->respond_json( {
               user_fields     => [qw( field1 field2 )],
               location_fields => [qw( field3 )],
               icon            => "mxc://1234/56/7",
               instances       => [
                  { desc => "instance 1" },
                  { desc => "instance 2" },
               ],
            } );

            Future->done(1);
         }),
         $appserv2->await_http_request( AS_PREFIX . "/thirdparty/protocol/ymca",
            sub { 1 },
         )->then( sub {
            my ( $request ) = @_;

            $request->respond_json( {
               user_fields     => [qw( field1 field2 )],
               location_fields => [qw( field3 )],
               icon            => "mxc://1234/56/7",
               instances       => [
                  { desc => "instance 3" },
               ],
            } );

            Future->done(1);
         }),

         do_request_json_for( $user,
            method => "GET",
            uri    => "/unstable/thirdparty/protocols"
         )->then( sub {
            my ( $body ) = @_;

            log_if_fail "protocols", $body;

            assert_json_object( $body );
            assert_ok( defined $body->{ymca}, 'HS knows "ymca" protocol' );

            my $ymca = $body->{ymca};
            # sort the instances list for consistency
            $ymca->{instances} = [ sort_by { $_->{desc} } @{ $ymca->{instances} } ];

            assert_deeply_eq( $body->{ymca},
               {
                  user_fields     => [qw( field1 field2 )],
                  location_fields => [qw( field3 )],
                  icon            => "mxc://1234/56/7",
                  instances       => [
                     { desc => "instance 1" },
                     { desc => "instance 2" },
                     { desc => "instance 3" },
                  ],
               },
               'fields in 3PE lookup metadata'
            );

            Future->done(1);
         }),
      );
   };

test "HS will proxy request for 3PU mapping",
   requires => [ local_user_fixture(), $main::APPSERV[0], $main::APPSERV[1],
                 qw( can_get_3pe_metadata )],

   do => sub {
      my ( $user, $appserv1, $appserv2 ) = @_;

      Future->needs_all(
         $appserv1->await_http_request( AS_PREFIX . "/thirdparty/user/ymca",
            sub { 1 }
         )->then( sub {
            my ( $request ) = @_;

            assert_deeply_eq(
               { $request->query_form },
               {
                  field1 => "ONE",
                  field2 => "TWO",
               },
               'fields in received AS request'
            );

            $request->respond_json( [
               {
                  protocol => "ymca",
                  fields   => { field1 => "result" },
                  userid   => '@remote-user:bridged.example.com',
               }
            ] );

            Future->done(1);
         }),
         stub_empty_result( $appserv2, "/thirdparty/user/ymca" ),

         do_request_json_for( $user,
            method => "GET",
            uri    => "/unstable/thirdparty/user/ymca",

            params => {
               field1 => "ONE",
               field2 => "TWO",
            }
         )->then( sub {
            my ( $body ) = @_;

            log_if_fail "Lookup result", $body;

            assert_deeply_eq(
               $body,
               [
                  {
                     protocol => "ymca",
                     fields   => { field1 => "result" },
                     userid   => '@remote-user:bridged.example.com',
                  }
               ],
               '3PU lookup result'
            );

            Future->done(1);
         }),
      )
   };

test "HS will proxy request for 3PL mapping",
   requires => [ local_user_fixture(), $main::APPSERV[0], $main::APPSERV[1],
                 qw( can_get_3pe_metadata )],

   do => sub {
      my ( $user, $appserv1, $appserv2 ) = @_;

      Future->needs_all(
         $appserv1->await_http_request( AS_PREFIX . "/thirdparty/location/ymca",
            sub { 1 }
         )->then( sub {
            my ( $request ) = @_;

            assert_deeply_eq(
               { $request->query_form },
               {
                  field3 => "THREE",
               },
               'fields in received AS request'
            );

            $request->respond_json( [
               {
                  protocol => "ymca",
                  fields   => { field3 => "result" },
                  alias    => '#remote-room:bridged.example.com',
               }
            ] );

            Future->done(1);
         }),
         stub_empty_result( $appserv2, "/thirdparty/location/ymca" ),

         do_request_json_for( $user,
            method => "GET",
            uri    => "/unstable/thirdparty/location/ymca",

            params => {
               field3 => "THREE",
            }
         )->then( sub {
            my ( $body ) = @_;

            log_if_fail "Lookup result", $body;

            assert_deeply_eq(
               $body,
               [
                  {
                     protocol => "ymca",
                     fields   => { field3 => "result" },
                     alias    => '#remote-room:bridged.example.com',
                  }
               ],
               '3PL lookup result'
            );

            Future->done(1);
         }),
      )
   };
