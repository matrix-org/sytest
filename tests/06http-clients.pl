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
   requires => [qw( synapse_client_locations )],

   setup => sub {
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

      Future->done( \@clients );
   },
);
