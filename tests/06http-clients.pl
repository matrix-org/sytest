use SyTest::HTTPClient;

push our @EXPORT, qw( HTTP_CLIENT );

our $HTTP_CLIENT = fixture(
   setup => sub {
      # Generic NaHTTP client, with SSL verification turned off, in case tests
      # need to speak plain HTTP(S) to an endpoint

      my $http_client = SyTest::HTTPClient->new;

      $loop->add( $http_client );

      Future->done( $http_client );
   },
);

prepare "Creating test Matrix HTTP clients",
   requires => [qw( synapse_client_locations )],

   provides => [qw( api_clients first_api_client )],

   do => sub {
      my ( $locations ) = @_;

      my @clients = map {
         my $location = $_;

         my $client = SyTest::HTTPClient->new(
            max_connections_per_host => 3,
            uri_base => "$location/_matrix/client",
         );
         $loop->add( $client );

         $client;
      } @$locations;

      provide api_clients => \@clients;
      provide first_api_client => $clients[0];

      Future->done;
   };
