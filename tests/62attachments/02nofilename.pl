my $content_id;

test "Can upload without a file name",
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
         }
      )->then(sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( content_uri ));

         my $content_uri = URI->new( $body->{content_uri} );
         my $server = $content_uri->authority;
         my $path = $content_uri->path;

         $content_id = "$server$path";

         Future->done(1)
      });
   };

test "Can download without a file name",
   requires => [qw( first_v1_client )],

   check => sub {
      my ( $http ) = @_;

      $http->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/$content_id",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         defined $disposition and
            die "Unexpected Content-Disposition header";

         Future->done(1);
      });
   };

test "Can download without a file name over federation",
   requires => [qw( v1_clients )],

   check => sub {
      my ( $clients ) = @_;

      $clients->[1]->do_request(
         method   => "GET",
         full_uri => "/_matrix/media/v1/download/$content_id",
      )->then( sub {
         my ( $body, $response ) = @_;

         my $disposition = $response->header( "Content-Disposition" );
         defined $disposition and
            die "Unexpected Content-Disposition header";

         Future->done(1);
      });
   };
