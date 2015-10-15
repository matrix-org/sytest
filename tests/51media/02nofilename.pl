my $content_id;

test "Can upload without a file name",
   requires => [qw( first_api_client ), local_user_preparer() ],

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

# These next two tests do the same thing with two different HTTP clients, to
# test locally and via federation

sub test_using_client
{
   my ( $client ) = @_;

   $client->do_request(
      method   => "GET",
      full_uri => "/_matrix/media/v1/download/$content_id",
   )->then( sub {
      my ( $body, $response ) = @_;

      my $disposition = $response->header( "Content-Disposition" );
      defined $disposition and
         die "Unexpected Content-Disposition header";

      Future->done(1);
   });
}

test "Can download without a file name locally",
   requires => [qw( first_api_client )],

   check => sub {
      my ( $http ) = @_;
      test_using_client( $http );
   };

test "Can download without a file name over federation",
   requires => [qw( api_clients )],

   check => sub {
      my ( $clients ) = @_;
      test_using_client( $clients->[1] );
   };
