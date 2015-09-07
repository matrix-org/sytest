test "Can upload with ascii file name",
   requires => [qw( first_v1_client user )],

   provides => [qw( ascii_content_id )],

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

         provide ascii_content_id => "$server$path";

         Future->done(1)
      });
   };

test "Can download with ascii file name",
   requires => [qw( first_v1_client ascii_content_id )],

   check => sub {
      my ( $http, $content_id ) = @_;

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

test "Can download specifying a ascii file name",
   requires => [qw( first_v1_client ascii_content_id )],

   check => sub {
      my ( $http, $content_id ) = @_;

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

test "Can download with ascii file name over federation",
   requires => [qw( v1_clients ascii_content_id )],

   check => sub {
      my ( $clients, $content_id ) = @_;

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
