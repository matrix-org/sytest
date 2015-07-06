use SyTest::HTTPClient;

prepare "Creating test HTTP clients",
   requires => [qw( synapse_client_locations )],

   provides => [qw( v1_clients first_v1_client v2_clients first_v2_client )],

   do => sub {
      my ( $locations ) = @_;

      my @v1_clients = map {
         my $location = $_;
         my $client = SyTest::HTTPClient->new(
            max_connections_per_host => 3,
            uri_base => "$location/_matrix/client/api/v1",
         );
         $loop->add( $client );
         $client;
      } @$locations;

      provide v1_clients => \@v1_clients;
      provide first_v1_client => $v1_clients[0];

      my @v2_clients = map {
         my $location = $_;
         my $client = SyTest::HTTPClient->new(
            uri_base => "$location/_matrix/client/v2_alpha",
         );
         $loop->add( $client );
         $client;
      } @$locations;

      provide v2_clients => \@v2_clients;
      provide first_v2_client => $v2_clients[0];

      Future->done;
   };
