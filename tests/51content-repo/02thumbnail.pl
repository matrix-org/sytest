use File::Basename qw( dirname );
use File::Slurp::Tiny qw( read_file );

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

         log_if_fail "Thumbnail", $body;

         # TODO: test that it looks about right somehow
         Future->done(1);
      });
   };
