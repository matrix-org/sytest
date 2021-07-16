use JSON qw( decode_json );

test "POST rejects invalid utf-8 in JSON",
   requires => [ $main::API_CLIENTS[0] ],

   do => sub {
      my ( $http ) = @_;

      my $reqbody = '{ "username": "a' . chr(0x81) . '" }';

      $http->do_request(
         method => "POST",
         uri    => "/r0/register",

         content => $reqbody,
         content_type =>"application/json",
      )->main::expect_http_400()
      ->then( sub {
         my ( $response ) = @_;
         my $body = decode_json( $response->content );
         assert_eq( $body->{errcode}, "M_NOT_JSON", 'responsecode' );
         Future->done( 1 );
      });
   };
