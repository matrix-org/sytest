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

# TODO: This ought to be an array, one per homeserver; though that's hard to
#   arrange currently
our $API_CLIENTS = fixture(
   requires => [ $main::HOMESERVER_INFO ],

   setup => sub {
      my ( $info ) = @_;

      my @clients = map {
         my $location = $_->client_location;

         my $client = SyTest::HTTPClient->new(
            max_connections_per_host => 3,
            uri_base => "$location/_matrix/client",
            server_name => $_->server_name,
         );
         $loop->add( $client );

         $client;
      } @$info;

      Future->done( \@clients );
   },
);
