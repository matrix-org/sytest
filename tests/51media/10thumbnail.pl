use File::Basename qw( dirname );
use File::Slurper qw( read_binary );

my $dir = dirname __FILE__;

test "POSTed media can be thumbnailed",
   requires => [ $main::API_CLIENTS[0], local_user_fixture(),
                 qw( can_upload_media can_download_media )],

   do => sub {
      my ( $http, $user ) = @_;

      my $pngdata = read_binary( "$dir/test.png" );

      # Because we're POST'ing non-JSON
      $http->do_request(
         method => "POST",
         full_uri => "/_matrix/media/r0/upload",
         params => {
            access_token => $user->access_token,
         },

         content_type => "image/png",
         content      => $pngdata,
      )->then( sub {
         my ( $body ) = @_;

         my $content_uri = URI->new( $body->{content_uri} );

         $http->do_request(
            method => "GET",
            full_uri => "/_matrix/media/r0/thumbnail/" .
               join( "", $content_uri->authority, $content_uri->path ),
            params => {
               width  => 32,
               height => 32,
               method => "scale",
            }
         )
      })->then( sub {
         my ( $body, $response ) = @_;

         for( $response->content_type ) {
            m{^image/png$} and validate_png( $body ), last;

            # TODO: should probably write a JPEG recogniser too

            warn "Unrecognised Content-Type ($_) - unable to detect if this is a valid image";
         }

         Future->done(1);
      });
   };

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
