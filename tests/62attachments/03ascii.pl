my $content_id;

test "Can upload with ASCII file name",
   requires => [qw( first_v1_client user )],

   do => sub {
      my ( $http, $user ) = @_;

      $http->do_request(
         method       => "POST",
         full_uri     => "/_matrix/media/v1/upload",
         content      => "Test media file",
         content_type => "text/plain",

         params => {
            access_token => $user->access_token,
            filename => "ascii",
         }
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( content_uri ));

         my $content_uri = URI->new( $body->{content_uri} );
         my $server = $content_uri->authority;
         my $path = $content_uri->path;

         $content_id = "$server$path";

         Future->done(1)
      });
   };

test "Can download with ASCII file name",
   requires => [qw( first_v1_client )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/$content_id",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         $disposition eq "inline; filename=ascii" or
            die "Expected a UTF-8 filename parameter";

         Future->done(1);
      });
   };

test "Can download specifying a ASCII file name",
   requires => [qw( first_v1_client )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/$content_id/also_ascii",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         $disposition eq "inline; filename=also_ascii" or
            die "Expected a UTF-8 filename parameter";

         Future->done(1);
      });
   };

test "Can download with ASCII file name over federation",
   requires => [qw( v1_clients )],

   check => sub {
      my ( $clients ) = @_;

      $clients->[1]->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/$content_id",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         $disposition eq "inline; filename=ascii" or
            die "Expected a UTF-8 filename parameter: $disposition";

         Future->done(1);
      });
   };
