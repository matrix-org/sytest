my $content_id;

test "Can upload without a file name",
   requires => [ $main::API_CLIENTS, local_user_fixture() ],

   do => sub {
      my ( $clients, $user ) = @_;
      my $http = $clients->[0];

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

         assert_json_keys( $body, qw( content_uri ));

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
   requires => [ $main::API_CLIENTS ],

   check => sub {
      my ( $clients ) = @_;
      test_using_client( $clients->[0] );
   };

test "Can download without a file name over federation",
   requires => [ $main::API_CLIENTS ],

   check => sub {
      my ( $clients ) = @_;
      test_using_client( $clients->[1] );
   };
