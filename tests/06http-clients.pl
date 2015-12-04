use SyTest::HTTPClient;

push our @EXPORT, qw( HTTP_CLIENT API_CLIENTS );

our $HTTP_CLIENT = fixture(
   setup => sub {
      # Generic NaHTTP client, with SSL verification turned off, in case tests
      # need to speak plain HTTP(S) to an endpoint

      my $http_client = SyTest::HTTPClient->new;

      $loop->add( $http_client );

      Future->done( $http_client );
   },
);

our @API_CLIENTS = map {
   my $info_fixture = $_;

   fixture(
      requires => [ $info_fixture ],

      setup => sub {
         my ( $info ) = @_;

         my $location = $info->client_location;

         my $client = SyTest::HTTPClient->new(
            max_connections_per_host => 3,
            uri_base => "$location/_matrix/client",
            server_name => $info->server_name,
         );
         $loop->add( $client );

         Future->done( $client );
      },
   );
} @main::HOMESERVER_INFO;
