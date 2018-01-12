use File::Basename qw( dirname );
use File::Slurper qw( read_binary );

my $dir = dirname __FILE__;

test "POSTed media can be thumbnailed",
   requires => [ $main::API_CLIENTS[0], local_user_fixture(),
                 qw( can_upload_media can_download_media )],

   do => sub {
      my ( $http, $user ) = @_;

      upload_test_image(
         $user,
      )->then( sub {
         my ( $content_uri ) = @_;
         fetch_and_validate_thumbnail( $http, $content_uri );
      });
   };


test "Remote media can be thumbnailed",
   requires => [ local_user_fixture(), remote_user_fixture(),
                 qw( can_upload_media can_download_media )],
   do => sub {
      my ( $local_user, $remote_user ) = @_;

      upload_test_image(
         $local_user,
      )->then( sub {
         my ( $content_uri ) = @_;
         fetch_and_validate_thumbnail( $remote_user->http, $content_uri );
      });
   };


sub upload_test_image
{
   my ( $user ) = @_;

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

sub fetch_and_validate_thumbnail
{
   my ( $http, $mxc_uri ) = @_;

   return $http->do_request(
      method => "GET",
      full_uri => "/_matrix/media/r0/thumbnail/" .
         join( "", $mxc_uri->authority, $mxc_uri->path ),
      params => {
         width  => 32,
         height => 32,
         method => "scale",
      }
   )->then( sub {
       my ( $body, $response ) = @_;
       for( $response->content_type ) {
          m{^image/png$} and validate_png( $body ), last;

          # TODO: should probably write a JPEG recogniser too

          die "Unrecognised Content-Type ($_) - unable to detect if this is a valid image";
       }

       Future->done(1);
   });
}

# We won't assert too heavily that it's a valid image as that's hard to do
# without using a full image parsing library like Imager. Instead we'll just
# detect file magic of a likely-valid encoding as this should cover most common
# implementation bugs, such as sending plain-text error messages with image
# MIME headers, or claiming one MIME type while being another.

sub validate_png
{
   my ( $body ) = @_;

   # All PNG images begin with the same 8 byte header
   $body =~ s/^\x89PNG\x0D\x0A\x1A\x0A// or
      die "Invalid PNG magic";

   # All PNG images have an IHDR header first. This header is 13 bytes long
   $body =~ s/^\0\0\0\x0DIHDR// or
      die "Invalid IHDR chunk";

   return 1;
}
