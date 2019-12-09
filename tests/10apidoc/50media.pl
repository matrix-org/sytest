use File::Basename qw( dirname );
use File::Slurper qw( read_binary );

=head2 upload_test_content

   my ( $content_id, $content_uri ) = upload_test_content(
      $user, filename => "filename",
   ) -> get;

Uploads some plaintext test content with the given filename.

Returns the content id of the uploaded content.

=cut
sub upload_test_content
{
   my ( $user, %params ) = @_;

   $user->http->do_request(
      method       => "POST",
      full_uri     => "/_matrix/media/r0/upload",
      content      => "Test media file",
      content_type => "text/plain",

      params => {
         access_token => $user->access_token,
         %params,
      },
   )->then( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, qw( content_uri ));

      my $content_uri = $body->{content_uri};

      my $parsed_uri = URI->new( $body->{content_uri} );
      my $server = $parsed_uri->authority;
      my $path = $parsed_uri->path;

      my $content_id = "$server$path";

      Future->done( $content_id, $content_uri );
   });
}
push our @EXPORT, qw( upload_test_content );

=head2 get_media

   my ( $content_disposition_params, $content ) = get_media( $http, $content_id ) -> get;

Fetches a piece of media from the server.

=cut
sub get_media
{
   my ( $http, $content_id ) = @_;

   $http->do_request(
      method   => "GET",
      full_uri => "/_matrix/media/r0/download/$content_id",
   )->then( sub {
      my ( $body, $response ) = @_;

      my $disposition = $response->header( "Content-Disposition" );

      my $cd_params;
      if ( defined $disposition ) {
         $cd_params = parse_content_disposition_params( $disposition );
      }
      Future->done( $cd_params, $body );
   });
}
push @EXPORT, qw( get_media );

=head2 upload_test_image

   my ( $content_uri ) = upload_test_image(
      $user,
   ) -> get;

Uploads a test image to the media store as the given user.

Returns the content uri of the uploaded content.

=cut
sub upload_test_image
{
   my ( $user ) = @_;

   my $dir = dirname __FILE__;
   my $pngdata = read_binary( "$dir/test.png" );

   # Because we're POST'ing non-JSON
   return $user->http->do_request(
      method => "POST",
      full_uri => "/_matrix/media/r0/upload",
      params => {
         access_token => $user->access_token,
      },

      content_type => "image/png",
      content      => $pngdata,
   )->then( sub {
      my ( $body ) = @_;
      log_if_fail "Upload response", $body;
      my $content_uri = URI->new( $body->{content_uri} );
      Future->done( $content_uri );
   });
}
push @EXPORT, qw( upload_test_image );

sub parse_content_disposition_params {
   my ( $disposition ) = @_;
   my @parts = split_header_words( $disposition );

   # should be only one list of words
   assert_eq( scalar @parts, 1, "number of content-dispostion header lists" );
   @parts = @{$parts[0]};

   # the first part must be 'inline'
   my $k = shift @parts;
   my $v = shift @parts;
   assert_eq( $k, "inline", "content-disposition" );
   die "invalid CD" if defined $v;

   my %params;
   while (@parts) {
      $k = shift @parts;
      $v = shift @parts;
      die "multiple $k params" if exists $params{$k};
      die "unknown param $k" unless ( $k eq 'filename' || $k eq 'filename*' );
      $params{$k} = $v;
   }
   return \%params;
}

