use SyTest::HTTPClient;

prepare "Creating test HTTP clients",
   requires => [qw( synapse_ports )],

   provides => [qw( http_clients first_http_client v2_clients first_v2_client )],

   ## TODO: This preparation step relies on sneaky visibility of the $NO_SSL
   #    variable defined at toplevel

   do => sub {
      my ( $ports ) = @_;

      my @clients = map {
         my $port = $_;
         my $client = SyTest::HTTPClient->new(
            uri_base => ( $NO_SSL ?
               "http://localhost:@{[ $port + 1000 ]}/_matrix/client/api/v1" :
               "https://localhost:$port/_matrix/client/api/v1" ),
         );
         $loop->add( $client );
         $client;
      } @$ports;

      provide http_clients => \@clients;
      provide first_http_client => $clients[0];

      my @v2_clients = map {
         my $port = $_;
         my $client = SyTest::HTTPClient->new(
            uri_base => ( $NO_SSL ?
               "http://localhost:@{[ $port + 1000 ]}/_matrix/client/v2_alpha" :
               "https://localhost:$port/_matrix/client/v2_alpha" ),
         );
         $loop->add( $client );
         $client;
      } @$ports;

      provide v2_clients => \@v2_clients;
      provide first_v2_client => $v2_clients[0];

      Future->done;
   };
