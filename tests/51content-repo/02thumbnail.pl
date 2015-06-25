use File::Basename qw( dirname );
use File::Slurp::Tiny qw( read_file );

use Imager;

my $dir = dirname __FILE__;

test "POSTed media can be thumbnailed",
   requires => [qw( first_http_client user
                    can_upload_media can_download_media )],

   do => sub {
      my ( $http, $user ) = @_;

      my $pngdata = read_file( "$dir/test.png" );

      # Because we're POST'ing non-JSON
      $http->do_request(
         method => "POST",
         full_uri => "/_matrix/media/v1/upload",
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
            full_uri => "/_matrix/media/v1/thumbnail/" .
               join( "", $content_uri->authority, $content_uri->path ),
            params => {
               width  => 32,
               height => 32,
               method => "scale",
            }
         )
      })->then( sub {
         my ( $body ) = @_;

         my $image = Imager->new( data => $body )
            or die "Unable to parse message body as image - " . Imager->errstr;

         # TODO: assert on the size

         Future->done(1);
      });
   };
